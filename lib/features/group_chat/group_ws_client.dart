import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef GroupWsHandler = void Function(Map<String, dynamic> event);

/// 群聊 WebSocket：ticket 连接 + ping 保活
class GroupWsClient {
  GroupWsClient({required this.wsUrl});

  final String wsUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  GroupWsHandler? onEvent;
  bool _closed = false;

  Future<void> connect() async {
    _closed = false;
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final map = jsonDecode(raw as String) as Map<String, dynamic>;
          onEvent?.call(map);
        } catch (_) {/* ignore malformed */}
      },
      onDone: () {
        if (!_closed) onEvent?.call({'type': '_closed'});
      },
      onError: (_) {
        if (!_closed) onEvent?.call({'type': '_error'});
      },
    );
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void sendChat(String content, {required String clientMsgId}) {
    send({
      'type': 'chat',
      'content': content,
      'client_msg_id': clientMsgId,
    });
  }

  void requestSync(String groupId, {int sinceSeq = 0}) {
    send({
      'type': 'sync',
      'group_id': groupId,
      'since_seq': sinceSeq,
    });
  }

  Future<void> dispose() async {
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
