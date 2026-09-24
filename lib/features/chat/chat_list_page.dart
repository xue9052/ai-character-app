import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/chat_local_store.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_fmt.dart';
import '../../widgets/unread_badge.dart';
import '../group_chat/group_chat_page.dart';
import '../group_chat/group_create_page.dart';
import '../group_chat/group_local_store.dart';
import '../group_chat/widgets/group_avatar.dart';
import '../personas/persona_cover.dart';
import 'chat_page.dart';

/// 会话列表：API 拉取 + AppState 乐观预览（返回立刻见最新一句）
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key, required this.isActive});

  /// 仅当前 Tab 可见时才拉会话列表接口。
  final bool isActive;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  List<_SessionRow> _rows = [];
  List<GroupSummaryDto> _groups = [];
  Map<String, int> _groupReadSeq = {};
  Map<String, int> _sessionReadTotal = {};
  bool _loading = false;
  String? _error;
  AppState? _state;
  int _lastChatVersion = -1;
  int _lastGroupVersion = -1;
  int _loadGen = 0;
  bool _loadedOnce = false;
  bool _dirty = false;

  @override
  void didUpdateWidget(ChatListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadIfNeeded();
    }
  }

  void _loadIfNeeded() {
    if (!widget.isActive) return;
    if (!_loadedOnce || _dirty) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppStateScope.of(context);
    if (!identical(_state, s)) {
      _state?.removeListener(_onState);
      _state = s;
      _state!.addListener(_onState);
      _lastChatVersion = s.chatListVersion;
      _lastGroupVersion = s.groupListVersion;
    }
    _loadIfNeeded();
  }

  @override
  void dispose() {
    _state?.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final s = _state;
    if (s == null || !mounted) return;
    if (s.chatListVersion != _lastChatVersion) {
      _lastChatVersion = s.chatListVersion;
      _lastGroupVersion = s.groupListVersion;
      setState(() => _rows = _mergePreviews(_rows, s));
      if (widget.isActive) {
        _load(silent: true);
      } else {
        _dirty = true;
      }
    } else if (s.groupListVersion != _lastGroupVersion) {
      _lastGroupVersion = s.groupListVersion;
      if (widget.isActive) {
        _load(silent: true);
      } else {
        _dirty = true;
      }
    }
  }

  Future<void> _syncGroupsFromCache(AppState s) async {
    if (!mounted) return;
    _mergeGroupsFromCache(s);
    await _refreshGroupReadSeq();
  }

  /// 群的最新 seq：WS 推送先落在 groupCache，可能比接口返回的更新。
  int _groupLastSeq(GroupSummaryDto g, AppState s) {
    final cached = s.groupCache[g.id];
    return cached != null && cached.lastSeq > g.lastSeq ? cached.lastSeq : g.lastSeq;
  }

  /// 基线取 DTO 自身的 lastSeq：传接口刚返回的群，本次会话里 WS 推来的增量才算未读。
  Future<Map<String, int>> _readSeqMapFor(List<GroupSummaryDto> groups) async {
    final readMap = <String, int>{};
    for (final g in groups) {
      readMap[g.id] = await GroupLocalStore.instance.ensureReadBaseline(
        g.id,
        g.lastSeq,
      );
    }
    return readMap;
  }

  Future<void> _refreshGroupReadSeq() async {
    if (_groups.isEmpty) return;
    final readMap = await _readSeqMapFor(_groups);
    if (!mounted) return;
    setState(() => _groupReadSeq = readMap);
  }

  /// 会话条数：本地乐观预览可能比接口返回的更新。
  int _sessionTotal(_SessionRow r, AppState s) {
    final preview = s.sessionPreviews[r.persona.id];
    return preview != null && preview.total > r.total ? preview.total : r.total;
  }

  Future<void> _refreshSessionReadTotals() async {
    final s = _state ?? AppStateScope.of(context);
    if (_rows.isEmpty) return;
    final readMap = <String, int>{};
    for (final r in _rows) {
      readMap[r.persona.id] = await ChatLocalStore.instance.ensureReadBaseline(
        s.userId,
        r.persona.id,
        _sessionTotal(r, s),
      );
    }
    if (!mounted) return;
    setState(() => _sessionReadTotal = readMap);
  }

  void _mergeGroupsFromCache(AppState s) {
    if (!mounted || s.groupCache.isEmpty) return;
    setState(() {
      _groups = s.groupCache.values.toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    });
  }

  List<_SessionRow> _mergePreviews(List<_SessionRow> base, AppState s) {
    final byId = {for (final r in base) r.persona.id: r};
    for (final preview in s.sessionPreviews.values) {
      final existing = byId[preview.personaId];
      if (existing != null) {
        final useLocal =
            preview.lastTs >= (existing.lastTs ?? 0) || existing.preview != preview.preview;
        if (useLocal) {
          byId[preview.personaId] = existing.copyWith(
            preview: preview.preview,
            lastTs: preview.lastTs,
            total: preview.total > existing.total ? preview.total : existing.total,
            stageLabel: existing.stageLabel,
          );
        }
      } else {
        byId[preview.personaId] = _SessionRow(
          persona: PersonaSummary(
            id: preview.personaId,
            name: preview.personaName,
            oneLiner: preview.oneLiner,
            source: 'custom',
          ),
          preview: preview.preview,
          total: preview.total,
          lastTs: preview.lastTs,
        );
      }
    }
    final rows = byId.values.toList()
      ..sort((a, b) {
        final ta = a.lastTs ?? 0;
        final tb = b.lastTs ?? 0;
        if (ta != tb) return tb.compareTo(ta);
        return b.total.compareTo(a.total);
      });
    return rows;
  }

  Future<void> _load({bool silent = false}) async {
    if (!widget.isActive) return;
    final gen = ++_loadGen;
    final s = _state ?? AppStateScope.of(context);

    // 本地会话表首屏（冷启动也能立刻看到聊过的人和群）
    if (!silent || (_rows.isEmpty && _groups.isEmpty)) {
      try {
        var local = await ChatLocalStore.instance.listInbox(s.userId);
        if (local.isEmpty) {
          local = await ChatLocalStore.instance.listSessions(s.userId);
        }
        if (gen != _loadGen || !mounted) return;
        if (local.isNotEmpty) {
          _applyInbox(local, s, gen, silent: true);
        }
      } catch (_) {/* ignore */}
    }

    if (!silent && mounted && _rows.isEmpty) {
      final previewRows = _rowsFromPreviews(s);
      setState(() {
        if (previewRows.isNotEmpty) _rows = previewRows;
        _loading = _rows.isEmpty;
        _error = null;
      });
    }
    try {
      final sessions = await s.api().listChatSessions(userId: s.userId, limit: 50);
      if (gen != _loadGen || !mounted) return;
      await ChatLocalStore.instance.saveInbox(s.userId, sessions);
      final direct = [
        for (final item in sessions)
          if ('${item['kind'] ?? 'direct'}' != 'group') item,
      ];
      await ChatLocalStore.instance.saveSessionsFromApi(s.userId, direct);
      if (gen != _loadGen || !mounted) return;
      _applyInbox(sessions, s, gen);
    } catch (e) {
      if (gen != _loadGen || !mounted) return;
      setState(() {
        _loading = false;
        if (_rows.isEmpty && _groups.isEmpty) _error = '$e';
      });
    }
  }

  void _applyInbox(
    List<Map<String, dynamic>> sessions,
    AppState s,
    int gen, {
    bool silent = false,
  }) {
    if (gen != _loadGen || !mounted) return;
    final direct = <Map<String, dynamic>>[];
    final groups = <GroupSummaryDto>[];
    final sessionRead = <String, int>{};
    final groupRead = <String, int>{};
    for (final item in sessions) {
      final kind = '${item['kind'] ?? 'direct'}';
      if (kind == 'group') {
        final id = '${item['peer_id'] ?? item['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final lastSeq = (item['last_seq'] as num?)?.toInt() ?? 0;
        final read = (item['read_seq'] as num?)?.toInt() ?? lastSeq;
        groupRead[id] = read;
        final covers = item['member_covers'];
        groups.add(
          GroupSummaryDto(
            id: id,
            title: '${item['title'] ?? ''}',
            coverUrl: '${item['cover_url'] ?? ''}',
            lastPreview: '${item['preview'] ?? item['last_preview'] ?? ''}',
            lastSeq: lastSeq,
            lastMessageAt: (item['last_ts'] as num?)?.toInt() ??
                (item['last_message_at'] as num?)?.toInt() ??
                0,
            canSend: item['can_send'] != false,
            memberCovers: [
              for (final u in (covers is List ? covers : const [])) '$u',
            ],
          ),
        );
      } else {
        direct.add(item);
        final pid = '${item['persona_id'] ?? item['peer_id'] ?? ''}'.trim();
        final total = (item['total_messages'] as num?)?.toInt() ??
            (item['last_seq'] as num?)?.toInt() ??
            0;
        final read = (item['read_seq'] as num?)?.toInt() ?? total;
        if (pid.isNotEmpty) sessionRead[pid] = read;
      }
    }
    setState(() {
      _rows = _mergePreviews(_rowsFromApiMaps(direct, s), s);
      _groups = groups;
      _sessionReadTotal = sessionRead;
      _groupReadSeq = groupRead;
      if (!silent) {
        _loading = false;
        _error = null;
        _loadedOnce = true;
        _dirty = false;
      } else {
        _loading = false;
        _loadedOnce = true;
        _error = null;
      }
    });
  }

  List<_SessionRow> _rowsFromApiMaps(
    List<Map<String, dynamic>> sessions,
    AppState s,
  ) {
    final rows = <_SessionRow>[];
    for (final item in sessions) {
      final pid = '${item['persona_id'] ?? ''}'.trim();
      if (pid.isEmpty) continue;
      final total = (item['total_messages'] as num?)?.toInt() ?? 0;
      if (total <= 0 && s.lastPersonaId != pid && s.sessionPreviews[pid] == null) {
        continue;
      }
      rows.add(
        _SessionRow(
          persona: PersonaSummary(
            id: pid,
            name: '${item['persona_name'] ?? pid}',
            oneLiner: '${item['one_liner'] ?? ''}',
            source: '${item['source'] ?? 'custom'}',
            coverUrl: item['cover_url'] as String?,
            coverEmoji: item['cover_emoji'] as String?,
            coverColor: item['cover_color'] as String?,
          ),
          preview: '${item['preview'] ?? '暂无消息，点此开始'}',
          total: total,
          lastTs: (item['last_ts'] as num?)?.toInt(),
          stageLabel: '${item['stage_label'] ?? ''}'.trim().isEmpty
              ? null
              : '${item['stage_label']}',
        ),
      );
    }
    return rows;
  }

  List<_SessionRow> _rowsFromPreviews(AppState s) {
    if (s.sessionPreviews.isEmpty) return [];
    final rows = <_SessionRow>[];
    for (final preview in s.sessionPreviews.values) {
      rows.add(
        _SessionRow(
          persona: PersonaSummary(
            id: preview.personaId,
            name: preview.personaName,
            oneLiner: preview.oneLiner ?? '',
            source: 'custom',
          ),
          preview: preview.preview,
          total: preview.total,
          lastTs: preview.lastTs,
        ),
      );
    }
    rows.sort((a, b) {
      final ta = a.lastTs ?? 0;
      final tb = b.lastTs ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return b.total.compareTo(a.total);
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSessionsLegacy(
    ApiClient api,
    AppState s,
  ) async {
    final personas = await api.listPersonas(s.userId);
    final out = <Map<String, dynamic>>[];
    for (final p in personas) {
      try {
        final chat = await api.getChat(
          userId: s.userId,
          personaId: p.id,
          limit: 5,
          allowFallback: false,
        );
        final msgs = (chat['messages'] as List?) ?? [];
        final total = chat['total_messages'] as int? ?? msgs.length;
        if (total <= 0 && s.lastPersonaId != p.id && s.sessionPreviews[p.id] == null) {
          continue;
        }
        var preview = '暂无消息，点此开始';
        int? lastTs;
        if (msgs.isNotEmpty) {
          final m = ChatMessageDto.fromJson(
            Map<String, dynamic>.from(msgs.last as Map),
          );
          final prefix = m.role == 'user' ? '我：' : '';
          final text = m.listPreviewText;
          preview = text.isEmpty ? '（新消息）' : '$prefix$text';
          lastTs = m.ts;
        }
        String stageLabel = '';
        try {
          final bond = await api.getBond(userId: s.userId, personaId: p.id);
          stageLabel = bond.stageLabel.trim();
        } catch (_) {}
        out.add({
          'persona_id': p.id,
          'persona_name': p.name,
          'one_liner': p.oneLiner,
          'cover_url': p.coverUrl,
          'cover_emoji': p.coverEmoji,
          'cover_color': p.coverColor,
          'source': p.source,
          'preview': preview,
          'total_messages': total,
          'last_ts': lastTs ?? 0,
          'stage_label': stageLabel,
        });
      } catch (_) {}
    }
    return out;
  }

  Future<void> _loadGroups({bool silent = false}) async {
    final s = _state ?? AppStateScope.of(context);
    if (s.groupChatConfig?.enabled != true) {
      if (mounted && _groups.isNotEmpty) {
        setState(() => _groups = []);
      }
      return;
    }
    if (s.groupCache.isNotEmpty && silent) {
      _mergeGroupsFromCache(s);
    }
    try {
      final groups = await s.api().listGroups();
      // 先用接口值建已读基线，再并入 WS 缓存，这样缓存里的增量才会算成未读
      final readMap = await _readSeqMapFor(groups);
      s.cacheGroups(groups);
      final merged = s.groupCache.values.toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      if (!mounted) return;
      setState(() {
        _groups = merged;
        _groupReadSeq = readMap;
      });
    } catch (_) {
      if (!silent && mounted && _groups.isEmpty) {
        // 灰度未开或网络失败：静默
      }
    }
  }

  List<_ChatListEntry> _mergedEntries() {
    final out = <_ChatListEntry>[];
    for (final r in _rows) {
      out.add(_ChatListEntry.session(r));
    }
    for (final g in _groups) {
      out.add(_ChatListEntry.group(g));
    }
    out.sort((a, b) => b.sortTs.compareTo(a.sortTs));
    return out;
  }

  Future<void> _openCreateGroup() async {
    final s = AppStateScope.of(context);
    try {
      final candidates = await s.api().getGroupCandidates();
      if (!mounted) return;
      if (candidates.length < 2) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgDarkElevated,
            title: const Text('还不能建群'),
            content: const Text(
              '建群需要至少 2 个自己创建的数字人。\n'
              '请先到「我的角色」创建更多角色后再试。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败：$e')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupCreatePage()),
    );
    if (!mounted) return;
    await _load(silent: true);
    AppStateScope.of(context).notifyGroupListUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final groupOn = s.groupChatConfig?.enabled == true;
    final entries = _mergedEntries();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('最近聊天'),
        backgroundColor: Colors.transparent,
        actions: [
          if (groupOn)
            IconButton(
              tooltip: '建群',
              onPressed: _openCreateGroup,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        // _load 内部已并行拉群聊，不必再单独拉一次
        onRefresh: _load,
        child: _buildBody(entries, groupOn),
      ),
    );
  }

  Widget _buildBody(List<_ChatListEntry> entries, bool groupOn) {
    if (_loading && entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text('加载失败：$_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: () => _load(), child: const Text('重试')),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 48,
            color: AppColors.primaryLight.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有会话',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            groupOn
                ? '去「首页」选一个，或点右上角建群'
                : '去「首页」里选一个，或自己创建一个再开聊',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 72,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e.isGroup) {
          return _buildGroupTile(e.group!, AppStateScope.of(context));
        }
        return _buildSessionTile(e.session!);
      },
    );
  }

  Widget _buildGroupTile(GroupSummaryDto g, AppState s) {
    final time = formatRelativeTime(g.lastMessageAt);
    final lastSeq = _groupLastSeq(g, s);
    // 已读位点还没读出来时按「无未读」，避免首帧闪一下整段历史的红点
    final read = _groupReadSeq[g.id] ?? lastSeq;
    final unreadCount = (lastSeq - read).clamp(0, 999999);
    final preview = g.lastPreview.isNotEmpty ? g.lastPreview : '暂无消息，点此开始';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          GroupAvatar(
            baseUrl: s.baseUrl,
            coverUrl: g.coverUrl,
            memberCovers: g.effectiveMemberCovers,
            radius: 26,
          ),
          if (unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: UnreadBadge(count: unreadCount),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              g.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.glassSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              '群',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (time.isNotEmpty)
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
            ),
        ],
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      onTap: () async {
        final app = AppStateScope.of(context);
        setState(() => _groupReadSeq[g.id] = lastSeq);
        unawaited(
          app.api().markInboxRead(userId: app.userId, kind: 'group', peerId: g.id),
        );
        if (!g.canSend) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.bgDarkElevated,
              title: const Text('暂时无法聊天'),
              content: const Text(
                '群里有效成员不足 2 人，无法继续对话。\n'
                '请先到群设置里添加成员，或创建新的群。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupChatPage(group: g),
          ),
        );
        if (!mounted) return;
        await _load(silent: true);
      },
    );
  }

  Widget _buildSessionTile(_SessionRow r) {
    final time = formatRelativeTime(r.lastTs);
    final s = AppStateScope.of(context);
    final total = _sessionTotal(r, s);
    // 已读位点还没读出来时按「无未读」，避免首帧闪一下整段历史的红点
    final readTotal = _sessionReadTotal[r.persona.id] ?? total;
    final unreadCount = (total - readTotal).clamp(0, 999999);
    final coverHex =
        (r.persona.coverColor ?? '#7B6CF6').replaceFirst('#', '');
    Color coverBg = AppColors.primary;
    try {
      coverBg = Color(int.parse(coverHex, radix: 16) + 0xFF000000);
    } catch (_) {/* keep default */}
    final fallback = (r.persona.coverEmoji != null &&
            r.persona.coverEmoji!.isNotEmpty)
        ? r.persona.coverEmoji!
        : (r.persona.name.isNotEmpty ? r.persona.name.substring(0, 1) : '?');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          PersonaCoverAvatar(
            baseUrl: s.baseUrl,
            coverUrl: r.persona.coverUrl,
            fallbackColor: coverBg,
            fallbackLabel: fallback,
            radius: 26,
          ),
          if (unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: UnreadBadge(count: unreadCount),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              r.persona.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if ((r.stageLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.glassSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                r.stageLabel!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          if (time.isNotEmpty)
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
            ),
        ],
      ),
      subtitle: Text(
        r.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      onTap: () async {
        final s = AppStateScope.of(context);
        setState(() => _sessionReadTotal[r.persona.id] = total);
        unawaited(
          s.api().markInboxRead(
            userId: s.userId,
            kind: 'direct',
            peerId: r.persona.id,
          ),
        );
        await s.setLastPersona(r.persona.id);
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              personaId: r.persona.id,
              personaName: r.persona.name,
              personaOneLiner: r.persona.oneLiner,
              personaCoverUrl: r.persona.coverUrl,
              personaCoverEmoji: r.persona.coverEmoji,
              personaCoverColor: r.persona.coverColor,
            ),
          ),
        );
        if (!mounted) return;
        setState(() => _rows = _mergePreviews(_rows, s));
        _load(silent: true);
      },
    );
  }
}

class _ChatListEntry {
  _ChatListEntry._({this.session, this.group});

  factory _ChatListEntry.session(_SessionRow row) =>
      _ChatListEntry._(session: row);
  factory _ChatListEntry.group(GroupSummaryDto g) =>
      _ChatListEntry._(group: g);

  final _SessionRow? session;
  final GroupSummaryDto? group;

  bool get isGroup => group != null;

  int get sortTs =>
      isGroup ? (group!.lastMessageAt) : (session!.lastTs ?? 0);
}

class _SessionRow {
  _SessionRow({
    required this.persona,
    required this.preview,
    required this.total,
    this.lastTs,
    this.stageLabel,
  });

  final PersonaSummary persona;
  final String preview;
  final int total;
  final int? lastTs;
  final String? stageLabel;

  _SessionRow copyWith({
    String? preview,
    int? total,
    int? lastTs,
    String? stageLabel,
  }) {
    return _SessionRow(
      persona: persona,
      preview: preview ?? this.preview,
      total: total ?? this.total,
      lastTs: lastTs ?? this.lastTs,
      stageLabel: stageLabel ?? this.stageLabel,
    );
  }
}
