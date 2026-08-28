import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_page.dart';
import 'persona_cover.dart';
import 'persona_detail_page.dart';
import 'persona_editor_page.dart';
import 'review_badge.dart';

/// 我的角色中心：自己创建的全部角色 + 审核角标
class PersonaWorkshopPage extends StatefulWidget {
  const PersonaWorkshopPage({super.key});

  @override
  State<PersonaWorkshopPage> createState() => _PersonaWorkshopPageState();
}

class _PersonaWorkshopPageState extends State<PersonaWorkshopPage> {
  Future<List<PersonaSummary>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  Future<List<PersonaSummary>> _fetch() {
    final s = AppStateScope.of(context);
    return AppStateScope.of(context).api().listMyPersonas(s.userId);
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openCreate() async {
    final saved = await Navigator.of(context).push<PersonaDetail>(
      MaterialPageRoute(builder: (_) => const PersonaEditorPage()),
    );
    if (saved != null && mounted) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.visibility == 'private'
                ? '已保存（仅自己可见）'
                : '已提交公开审核，通过后其他人才能在广场看到',
          ),
        ),
      );
    }
  }

  Future<void> _openEdit(PersonaSummary p) async {
    final saved = await Navigator.of(context).push<PersonaDetail>(
      MaterialPageRoute(builder: (_) => PersonaEditorPage(personaId: p.id)),
    );
    if (saved != null && mounted) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重新提交审核')),
      );
    }
  }

  List<PersonaSummary> _sorted(List<PersonaSummary> list) {
    int rank(PersonaSummary p) {
      if (p.isRejected) return 0;
      if (p.isPending) return 1;
      return 2;
    }

    final copy = [...list];
    copy.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('我的角色'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('创建角色'),
      ),
      body: FutureBuilder<List<PersonaSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载失败：${snap.error}'),
              ),
            );
          }
          final list = _sorted(snap.data ?? []);
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.theater_comedy_outlined, size: 48, color: scheme.outline),
                    const SizedBox(height: 12),
                    const Text('还没有创建角色'),
                    const SizedBox(height: 8),
                    Text(
                      '创建后会进入审核；通过后才会出现在角色广场供他人发现。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('创建角色'),
                    ),
                  ],
                ),
              ),
            );
          }

          final pending = list.where((p) => p.isPending).length;
          final rejected = list.where((p) => p.isRejected).length;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '未通过审核的角色仅自己可见。排序：未通过 → 审核中 → 已通过。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    if (pending > 0 || rejected > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (rejected > 0) '$rejected 个未通过',
                          if (pending > 0) '$pending 个审核中',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: rejected > 0 ? scheme.error : scheme.primary,
                            ),
                      ),
                    ],
                  ],
                );
              }
              final p = list[i - 1];
              final s = AppStateScope.of(context);
              final fallbackColor = Color(
                int.parse(
                      (p.coverColor ?? '#7B6CF6').replaceFirst('#', ''),
                      radix: 16,
                    ) +
                    0xFF000000,
              );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PersonaCoverAvatar(
                        baseUrl: s.baseUrl,
                        coverUrl: p.coverUrl,
                        fallbackColor: fallbackColor,
                        fallbackLabel:
                            p.name.isNotEmpty ? p.name.substring(0, 1) : '?',
                        radius: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PersonaDetailPage(personaId: p.id),
                              ),
                            );
                            if (mounted) _reload();
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ReviewBadge(status: p.reviewStatus, compact: true),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.oneLiner?.isNotEmpty == true
                                    ? p.oneLiner!
                                    : '自定义角色',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                reviewHint(p),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: p.isRejected
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                    ),
                              ),
                              if (p.isRejected || p.isPending) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => _openEdit(p),
                                    child: Text(p.isRejected ? '去修改并重提' : '继续编辑'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        child: const Text('聊天'),
                        onPressed: () async {
                          await s.setLastPersona(p.id);
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                personaId: p.id,
                                personaName: p.name,
                                personaOneLiner: p.oneLiner,
                                personaCoverUrl: p.coverUrl,
                                personaCoverEmoji: p.coverEmoji,
                                personaCoverColor: p.coverColor,
                                personaBackgroundKey: p.backgroundKey,
                                personaBackgroundUrl: p.backgroundUrl,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
