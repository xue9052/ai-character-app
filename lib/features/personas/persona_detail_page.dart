import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../chat/chat_page.dart';
import '../chat/chat_quick_replies.dart';
import 'persona_cover.dart';
import 'persona_editor_page.dart';
import 'review_badge.dart';

class PersonaDetailPage extends StatefulWidget {
  const PersonaDetailPage({super.key, required this.personaId});

  final String personaId;

  @override
  State<PersonaDetailPage> createState() => _PersonaDetailPageState();
}

class _PersonaDetailPageState extends State<PersonaDetailPage> {
  Future<PersonaDetail>? _future;
  final _previewPlayer = AudioPlayer();
  bool _previewLoading = false;

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<PersonaDetail> _load() {
    final s = AppStateScope.of(context);
    return AppStateScope.of(context).api().getPersona(s.userId, widget.personaId);
  }

  void _reload() => setState(() => _future = _load());

  String _previewText(PersonaDetail p) {
    for (final raw in [p.greeting, p.oneLiner]) {
      final t = (raw ?? '').trim();
      if (t.isNotEmpty) return t.length > 80 ? t.substring(0, 80) : t;
    }
    return '你好，我在呢。';
  }

  Future<void> _previewVoice(PersonaDetail p) async {
    if (_previewLoading) return;
    setState(() => _previewLoading = true);
    final s = AppStateScope.of(context);
    final text = _previewText(p);
    try {
      final data = await s.api().chatTts(
            userId: s.userId,
            personaId: p.id,
            messageId: 'preview_${p.id}',
            text: text,
            clip: true,
          );
      final rel = '${data['audio_url'] ?? ''}'.trim();
      if (rel.isEmpty) {
        throw ApiException('未返回音频');
      }
      final abs = resolvePersonaCoverUrl(s.baseUrl, rel) ?? rel;
      await _previewPlayer.stop();
      await _previewPlayer.play(UrlSource(abs));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('试听：$text')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('试听失败：${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  bool _owned(PersonaDetail p) {
    final uid = AppStateScope.of(context).userId;
    if (p.isOwnedBy(uid)) return true;
    // 兼容旧数据缺 owner：自定义且能拉到详情的通常是自己的
    return p.isCustom && (p.ownerUserId == null || p.ownerUserId == uid);
  }

  Future<void> _delete(PersonaDetail p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定删除「${p.name}」？聊天记录不会自动清除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = AppStateScope.of(context);
    try {
      await s.api().deletePersona(userId: s.userId, id: p.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色详情'),
        actions: [
          FutureBuilder<PersonaDetail>(
            future: _future,
            builder: (context, snap) {
              final p = snap.data;
              if (p == null || !_owned(p)) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final saved = await Navigator.of(context).push<PersonaDetail>(
                        MaterialPageRoute(
                          builder: (_) => PersonaEditorPage(personaId: p.id),
                        ),
                      );
                      if (saved != null && mounted) _reload();
                    },
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(p),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<PersonaDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            final msg = apiErrorMessage(snap.error!);
            final notFound = msg.contains('404') || msg.contains('not found');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      notFound ? '角色不存在或已删除' : '加载失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notFound
                          ? '后端找不到 ${widget.personaId}。\n'
                              '常见原因：上次保存时后端未更新/已重启丢数据，或会话里挂着旧角色。\n'
                              '请重启后端后重新创建角色。'
                          : msg,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data!;
          final owned = _owned(p);
          final baseUrl = AppStateScope.of(context).baseUrl;
          final coverBg = _coverColor(p);
          final emoji = (p.coverEmoji != null && p.coverEmoji!.isNotEmpty)
              ? p.coverEmoji!
              : (p.name.isNotEmpty ? p.name.substring(0, 1) : '?');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PersonaCoverBanner(
                baseUrl: baseUrl,
                coverUrl: p.coverUrl,
                fallbackColor: coverBg,
                fallbackLabel: emoji,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          PersonaCoverAvatar(
                            baseUrl: baseUrl,
                            coverUrl: p.coverUrl,
                            fallbackColor: coverBg,
                            fallbackLabel: emoji,
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        p.name,
                                        style: Theme.of(context).textTheme.headlineSmall,
                                      ),
                                    ),
                                    if (owned && p.isCustom) ...[
                                      const SizedBox(width: 8),
                                      ReviewBadge(status: p.reviewStatus),
                                    ],
                                  ],
                                ),
                                if (p.oneLiner != null && p.oneLiner!.isNotEmpty)
                                  Text(
                                    p.oneLiner!,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                if (owned && p.isCustom && (p.isPending || p.isRejected)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.isRejected
                          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.45)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      p.isPending
                          ? '审核中：通过后其他用户才能在广场看到。你仍可自己聊天与编辑；再次保存会重新进入待审。'
                          : (p.reviewReason?.isNotEmpty == true
                              ? '未通过：${p.reviewReason}\n请修改后重新保存提交审核。'
                              : '未通过审核。请修改设定后重新保存提交。'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.isRejected
                                ? Theme.of(context).colorScheme.onErrorContainer
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.definitionHidden ? '角色简介' : '角色设定',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.definitionHidden
                              ? (p.oneLiner?.isNotEmpty == true
                                  ? p.oneLiner!
                                  : '作者未公开完整设定，开始聊天即可体验。')
                              : (p.definition?.isNotEmpty == true
                                  ? p.definition!
                                  : '（暂无角色定义文本）'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (p.definitionHidden) ...[
                          const SizedBox(height: 8),
                          Text(
                            '完整人设仅作者可见，避免被直接复制。',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (p.greeting != null && p.greeting!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('主开场白', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(p.greeting!, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        if (p.alternateGreetings.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('备用开场', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          for (final g in p.alternateGreetings) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('· $g', style: Theme.of(context).textTheme.bodyMedium),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (p.hasTtsVoice)
                  OutlinedButton.icon(
                    onPressed: _previewLoading ? null : () => unawaited(_previewVoice(p)),
                    icon: _previewLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.volume_up_outlined),
                    label: Text(_previewLoading ? '生成中…' : '听她说一句'),
                  ),
                if (p.hasTtsVoice) const SizedBox(height: 12),
                Text(
                  '试聊一句',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tip in ChatQuickReplies.companionOpeners(
                      personaName: p.name,
                    ).take(4))
                      ActionChip(
                        label: Text(tip),
                        onPressed: () async {
                          final s = AppStateScope.of(context);
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
                                initialDraft: tip,
                                autoSendDraft: true,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FrostButton(
                  onPressed: () async {
                    final s = AppStateScope.of(context);
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
                  child: const Text('开始聊天'),
                ),
                if (owned) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final saved = await Navigator.of(context).push<PersonaDetail>(
                        MaterialPageRoute(
                          builder: (_) => PersonaEditorPage(personaId: p.id),
                        ),
                      );
                      if (saved != null && mounted) _reload();
                    },
                    child: const Text('编辑角色'),
                  ),
                ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _coverColor(PersonaDetail p) {
    final hex = (p.coverColor ?? '#7B6CF6').replaceFirst('#', '');
    try {
      return Color(int.parse(hex, radix: 16) + 0xFF000000);
    } catch (_) {
      return AppColors.bgDarkElevated;
    }
  }
}
