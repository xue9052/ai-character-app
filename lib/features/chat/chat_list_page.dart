import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/chat_local_store.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_fmt.dart';
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
  bool _loading = false;
  String? _error;
  AppState? _state;
  int _lastVersion = -1;
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
      _lastVersion = s.chatListVersion;
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
    if (s.chatListVersion != _lastVersion) {
      _lastVersion = s.chatListVersion;
      setState(() => _rows = _mergePreviews(_rows, s));
      if (widget.isActive) {
        _load(silent: true);
      } else {
        _dirty = true;
      }
    }
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

    // 本地 DB 首屏（冷启动也能立刻看到聊过的角色）
    if (!silent || _rows.isEmpty) {
      try {
        final local = await ChatLocalStore.instance.listSessions(s.userId);
        if (gen != _loadGen || !mounted) return;
        if (local.isNotEmpty) {
          final localRows = _rowsFromApiMaps(local, s);
          setState(() {
            _rows = _mergePreviews(localRows, s);
            _loading = false;
            _loadedOnce = true;
            _error = null;
          });
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
      final api = s.api();
      List<Map<String, dynamic>> sessions;
      try {
        sessions = await api.listChatSessions(userId: s.userId, limit: 50);
      } catch (_) {
        // 旧服务端无 /chat/sessions 时回退逐角色拉取
        sessions = await _loadSessionsLegacy(api, s);
      }
      if (gen != _loadGen || !mounted) return;
      await ChatLocalStore.instance.saveSessionsFromApi(s.userId, sessions);
      final rows = _rowsFromApiMaps(sessions, s);
      final merged = _mergePreviews(rows, s);
      if (gen != _loadGen || !mounted) return;
      setState(() {
        _rows = merged;
        _loading = false;
        _error = null;
        _loadedOnce = true;
        _dirty = false;
      });
    } catch (e) {
      if (gen != _loadGen || !mounted) return;
      setState(() {
        _loading = false;
        if (_rows.isEmpty) _error = '$e';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('最近聊天'),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _rows.isEmpty) {
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
    if (_rows.isEmpty) {
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
            '去「首页」里选一个，或自己创建一个再开聊',
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
      itemCount: _rows.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 72,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, i) {
        final r = _rows[i];
        final time = formatRelativeTime(r.lastTs);
        final s = AppStateScope.of(context);
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
          leading: PersonaCoverAvatar(
            baseUrl: s.baseUrl,
            coverUrl: r.persona.coverUrl,
            fallbackColor: coverBg,
            fallbackLabel: fallback,
            radius: 26,
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
                    color: AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    r.stageLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLight.withValues(alpha: 0.95),
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
            // 返回时再合并一次本地预览并静默刷新
            if (!mounted) return;
            setState(() => _rows = _mergePreviews(_rows, s));
            _load(silent: true);
          },
        );
      },
    );
  }
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
