import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../features/group_chat/group_local_store.dart';
import '../features/group_chat/group_ws_client.dart';
import 'app_state.dart';

typedef GroupWsEventHandler = void Function(Map<String, dynamic> event);

/// App 级群聊 IM：每用户一条 WebSocket，帧内 group_id 多路复用。
class GroupWsManager extends ChangeNotifier {
  GroupWsManager._();

  static final GroupWsManager instance = GroupWsManager._();

  AppState? _app;
  bool _paused = false;
  bool _syncing = false;
  bool _connecting = false;
  bool _connected = false;
  String? _activeGroupId;
  GroupWsClient? _client;
  Timer? _reconnectTimer;
  int _attempt = 0;
  final Set<String> _syncedGroups = {};
  final Map<String, Set<GroupWsEventHandler>> _listeners = {};

  String? get activeGroupId => _activeGroupId;

  bool isConnected(String groupId) =>
      _connected && _syncedGroups.contains(groupId.trim());

  bool isConnecting(String groupId) =>
      _connecting || (_connected && !isConnected(groupId));

  Future<void> start(AppState app) async {
    _app = app;
    if (_paused) return;
    await syncGroups();
  }

  Future<void> stop() async {
    _activeGroupId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _client?.dispose();
    _client = null;
    _connected = false;
    _connecting = false;
    _syncedGroups.clear();
    _app = null;
    notifyListeners();
  }

  void pause() {
    _paused = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_client?.dispose());
    _client = null;
    _connected = false;
    _connecting = false;
    _syncedGroups.clear();
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    final app = _app;
    if (app != null && app.isLoggedIn) {
      await syncGroups();
    }
  }

  /// 丢弃当前 socket 重连。长时间后台后 socket 可能已被系统静默掐断，
  /// 但 onDone/onError 不一定回调，此时只靠 [syncGroups] 会误判成已连接。
  Future<void> reconnect() async {
    if (_paused) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _client?.dispose();
    _client = null;
    _connected = false;
    _connecting = false;
    _attempt = 0;
    _syncedGroups.clear();
    notifyListeners();
    await syncGroups();
  }

  void setActiveGroup(String? groupId) {
    _activeGroupId = groupId;
  }

  void subscribe(String groupId, GroupWsEventHandler handler) {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    (_listeners[gid] ??= <GroupWsEventHandler>{}).add(handler);
  }

  void unsubscribe(String groupId, GroupWsEventHandler handler) {
    _listeners[groupId]?.remove(handler);
  }

  Future<void> syncGroups() async {
    final app = _app;
    if (app == null || !app.isLoggedIn || _paused) return;
    if (app.groupChatConfig?.enabled != true) {
      await stop();
      return;
    }
    if (_syncing) return;
    _syncing = true;
    try {
      final groups = await app.api().listGroups();
      app.cacheGroups(groups);
      await _ensureConnected();
      for (final g in groups) {
        await ensureGroup(g.id);
      }
    } catch (e) {
      debugPrint('[group-ws] sync failed: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> ensureGroup(String groupId) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    if (_connected && !_syncedGroups.contains(gid)) {
      _client?.requestSync(gid);
    } else if (!_connected && !_connecting) {
      await _ensureConnected();
    }
  }

  Future<void> _ensureConnected() async {
    if (_paused) return;
    final app = _app;
    if (app == null || !app.isLoggedIn) return;
    if (_connected || _connecting) return;

    _connecting = true;
    notifyListeners();
    try {
      final ticket = await app.api().issueGroupImWsTicket();
      final url = app.api().groupImWsUrl(ticket);
      await _client?.dispose();
      final client = GroupWsClient(wsUrl: url);
      client.onEvent = _onEvent;
      _client = client;
      await client.connect();
    } catch (e) {
      debugPrint('[group-ws] connect failed: $e');
      _connected = false;
      _connecting = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = '${event['type'] ?? ''}';
    if (type == '_closed' || type == '_error') {
      _connected = false;
      _connecting = false;
      _syncedGroups.clear();
      notifyListeners();
      _scheduleReconnect();
      return;
    }
    if (type == 'ready') {
      _connected = true;
      _connecting = false;
      _attempt = 0;
      notifyListeners();
      return;
    }
    if (type == 'snapshot') {
      final gid = '${event['group_id'] ?? ''}'.trim();
      if (gid.isNotEmpty) {
        _syncedGroups.add(gid);
        _connected = true;
        _connecting = false;
        _attempt = 0;
      }
    }
    _dispatch(event);
  }

  void _scheduleReconnect() {
    if (_paused || _app == null) return;
    _reconnectTimer?.cancel();
    _attempt++;
    final delay = Duration(
      seconds: (_attempt.clamp(1, 6) * 2).clamp(2, 30),
    );
    _reconnectTimer = Timer(delay, () {
      if (!_paused && _app != null) {
        unawaited(_ensureConnected());
      }
    });
  }

  void _dispatch(Map<String, dynamic> event) {
    final groupId = '${event['group_id'] ?? ''}'.trim();
    if (groupId.isEmpty) return;

    final type = '${event['type'] ?? ''}';
    if (type == 'message') {
      final raw = event['message'];
      if (raw is Map) {
        final msg = GroupMessageDto.fromJson(
          Map<String, dynamic>.from(raw),
        );
        unawaited(GroupLocalStore.instance.upsertMessages(groupId, [msg]));
        _app?.applyGroupMessage(groupId, msg);
        if (_activeGroupId == groupId) {
          unawaited(
            GroupLocalStore.instance.setLastReadSeq(groupId, msg.seq),
          );
        }
      }
    } else if (type == 'snapshot') {
      final msgs = [
        for (final m in (event['messages'] as List? ?? const []))
          GroupMessageDto.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      if (msgs.isNotEmpty) {
        unawaited(GroupLocalStore.instance.upsertMessages(groupId, msgs));
      }
      final lastSeq = (event['last_seq'] as num?)?.toInt();
      if (lastSeq != null && lastSeq > 0) {
        _app?.patchGroupLastSeq(groupId, lastSeq);
      }
    }

    final handlers = _listeners[groupId];
    if (handlers != null) {
      for (final h in handlers) {
        h(event);
      }
    }
    notifyListeners();
  }
}
