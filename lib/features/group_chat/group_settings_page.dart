import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../services/group_ws_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../chat/chat_top_bar.dart';
import '../personas/persona_cover.dart';
import 'group_memories_page.dart';
import 'widgets/group_avatar.dart';

class GroupSettingsPage extends StatefulWidget {
  const GroupSettingsPage({
    super.key,
    required this.group,
    this.onUpdated,
    this.onDissolved,
  });

  final GroupSummaryDto group;
  final ValueChanged<GroupSummaryDto>? onUpdated;
  final VoidCallback? onDissolved;

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  late GroupSummaryDto _group;
  final _titleCtrl = TextEditingController();
  bool _busy = false;
  List<PersonaSummary> _candidates = [];

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _titleCtrl.text = _group.title;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCandidates());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final s = AppStateScope.of(context);
      _candidates = await s.api().getGroupCandidates();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveTitle() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      final updated = await s.api().patchGroupTitle(_group.id, title);
      if (!mounted) return;
      setState(() {
        _group = updated;
        _busy = false;
      });
      widget.onUpdated?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('群名已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      final updated = await s.api().uploadGroupCover(
        _group.id,
        bytes: bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _group = updated;
        _busy = false;
      });
      widget.onUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _clearCover() async {
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      final updated = await s.api().deleteGroupCover(_group.id);
      if (!mounted) return;
      setState(() {
        _group = updated;
        _busy = false;
      });
      widget.onUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addMember(String personaId) async {
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      final updated = await s.api().addGroupMember(_group.id, personaId);
      if (!mounted) return;
      setState(() {
        _group = updated;
        _busy = false;
      });
      widget.onUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeMember(String personaId) async {
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      final updated = await s.api().removeGroupMember(_group.id, personaId);
      if (!mounted) return;
      setState(() {
        _group = updated;
        _busy = false;
      });
      widget.onUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _dissolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: const Text('解散群聊？'),
        content: const Text('聊天记录仍会保留在本地缓存，但无法再发消息。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('解散')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final s = AppStateScope.of(context);
      await s.api().dissolveGroup(_group.id);
      if (!mounted) return;
      widget.onDissolved?.call();
      AppStateScope.of(context).removeGroupFromCache(_group.id);
      unawaited(GroupWsManager.instance.syncGroups());
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Set<String> get _activeIds => _group.members
      .where((m) => m.active && !m.deleted)
      .map((m) => m.personaId)
      .toSet();

  List<PersonaSummary> get _addable => _candidates
      .where((p) => !_activeIds.contains(p.id))
      .toList();

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final listTop = ChatTopBar.listTopPadding(topInset);
    final memberCovers = _group.effectiveMemberCovers;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bgDarkElevated.withValues(alpha: 0.95),
                    AppColors.bgDark,
                    const Color(0xFF0A0B10),
                  ],
                ),
              ),
            ),
          ),
          ListView(
            padding: EdgeInsets.fromLTRB(20, listTop + 8, 20, 32),
            children: [
                    Center(
                      child: Column(
                        children: [
                          GroupAvatar(
                            baseUrl: s.baseUrl,
                            coverUrl: _group.coverUrl,
                            memberCovers: memberCovers,
                            radius: 40,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FrostButton(
                                height: 36,
                                expanded: false,
                                onPressed: _pickCover,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    '换头像',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                              if (_group.coverUrl.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                FrostButton(
                                  height: 36,
                                  expanded: false,
                                  onPressed: _clearCover,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      '清除',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('群名'),
                    FrostField(
                      controller: _titleCtrl,
                      hintText: '给这群起个名字',
                      maxLines: 1,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FrostButton(
                        height: 38,
                        expanded: false,
                        onPressed: _saveTitle,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            '保存群名',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.push_pin_outlined,
                        color: AppColors.accentPink,
                      ),
                      title: const Text('群记忆'),
                      subtitle: Text(
                        '查看一起记住的时刻',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupMemoriesPage(
                              groupId: _group.id,
                              groupTitle: _group.title,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('成员'),
                    ..._group.members.where((m) => m.active).map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FrostSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          radius: 16,
                          child: Row(
                            children: [
                              PersonaCoverAvatar(
                                baseUrl: s.baseUrl,
                                coverUrl: m.coverUrl,
                                fallbackColor: AppColors.bgDarkElevated,
                                fallbackLabel:
                                    m.name.isNotEmpty ? m.name.substring(0, 1) : '?',
                                radius: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (m.renamed)
                                      Text(
                                        '已改名（旧气泡仍显示当时的名字）',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.glassSoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m.tierLabel(),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              if (_activeIds.length > 2)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: FrostIconButton(
                                    icon: Icons.remove_circle_outline,
                                    onTap: () => _removeMember(m.personaId),
                                    size: 34,
                                    iconSize: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (_addable.isNotEmpty && _activeIds.length < 3) ...[
                      const SizedBox(height: 12),
                      _sectionTitle('添加成员'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _addable.map((p) {
                          return GestureDetector(
                            onTap: () => _addMember(p.id),
                            child: FrostSurface(
                              radius: 999,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PersonaCoverAvatar(
                                    baseUrl: s.baseUrl,
                                    coverUrl: p.coverUrl,
                                    fallbackColor: AppColors.bgDarkElevated,
                                    fallbackLabel:
                                        p.name.isNotEmpty ? p.name.substring(0, 1) : '?',
                                    radius: 12,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    p.name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 36),
                    FrostButton(
                      onPressed: _dissolve,
                      child: const Text(
                        '解散群聊',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ChatTopBar(
              topInset: topInset,
              child: Row(
                children: [
                  FrostIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '群设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
