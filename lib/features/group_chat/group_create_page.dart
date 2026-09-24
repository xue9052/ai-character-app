import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../services/group_ws_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../personas/persona_cover.dart';
import 'group_chat_page.dart';

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _titleCtrl = TextEditingController();
  List<PersonaSummary> _candidates = [];
  final _selected = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = AppStateScope.of(context);
      final list = await s.api().getGroupCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _create() async {
    if (_selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择 2–3 个自己创建的数字人')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    try {
      final data = await s.api().createGroup(
        personaIds: _selected.toList(),
        title: _titleCtrl.text.trim(),
      );
      if (!mounted) return;
      final reused = data['reused'] == true;
      AppStateScope.of(context).notifyGroupListUpdated();
      await GroupWsManager.instance.syncGroups();
      if (reused) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('这组成员已经有群了，请在聊天列表里打开'),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      final group = GroupSummaryDto.fromJson(
        Map<String, dynamic>.from(data['group'] as Map),
      );
      final msgs = [
        for (final m in (data['messages'] as List? ?? const []))
          GroupMessageDto.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      if (!mounted) return;
      AppStateScope.of(context).notifyGroupListUpdated();
      await GroupWsManager.instance.syncGroups();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            group: group,
            initialMessages: msgs,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _toggle(PersonaSummary p) {
    setState(() {
      if (_selected.contains(p.id)) {
        _selected.remove(p.id);
      } else if (_selected.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多选 3 人')),
        );
      } else {
        _selected.add(p.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('建群'),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '选 2–3 个你的数字人',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '只能选自己创建的角色，广场官角不能进群。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 20),
                    FrostField(
                      controller: _titleCtrl,
                      hintText: '群名（可选，默认用成员名）',
                      maxLines: 1,
                    ),
                    const SizedBox(height: 20),
                    if (_candidates.length < 2)
                      FrostSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('自建数字人还不够'),
                            const SizedBox(height: 8),
                            Text(
                              '先去「我的角色」创建至少 2 个，再回来建群。',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._candidates.map((p) {
                        final on = _selected.contains(p.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggle(p),
                              borderRadius: BorderRadius.circular(20),
                              child: FrostSurface(
                                tone: on ? FrostTone.light : FrostTone.smoke,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                radius: 20,
                                child: Row(
                                  children: [
                                    PersonaCoverAvatar(
                                      baseUrl: s.baseUrl,
                                      coverUrl: p.coverUrl,
                                      fallbackColor: AppColors.bgDarkElevated,
                                      fallbackLabel: p.name.isNotEmpty
                                          ? p.name.substring(0, 1)
                                          : '?',
                                      radius: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if ((p.oneLiner ?? '').isNotEmpty)
                                            Text(
                                              p.oneLiner!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      on
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: on
                                          ? AppColors.success
                                          : AppColors.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    FrostButton(
                      onPressed:
                          _candidates.length >= 2 && _selected.length >= 2
                              ? _create
                              : null,
                      child: Text('创建（${_selected.length}/3）'),
                    ),
                  ],
                ),
    );
  }
}
