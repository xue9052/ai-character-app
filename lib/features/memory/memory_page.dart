import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.personaId});

  final String personaId;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final _searchCtrl = TextEditingController();
  String _category = 'all';
  List<MemoryItemDto> _items = const [];
  bool _loading = true;
  String? _error;

  static const _categories = <(String, String)>[
    ('all', '全部'),
    ('scene', '场景'),
    ('biographical', '生平'),
    ('preference', '偏好'),
    ('relation', '关系'),
    ('event', '事件'),
    ('safety', '安全'),
    ('reflection', '反思'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = AppStateScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiCategory = _category == 'scene' ? 'event' : _category;
      var list = await s.api().listMemories(
        userId: s.userId,
        personaId: widget.personaId,
        category: apiCategory,
        q: _searchCtrl.text.trim(),
      );
      if (_category == 'scene') {
        list = list
            .where((m) => m.text.trim().startsWith('【'))
            .toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  Future<void> _togglePin(MemoryItemDto m) async {
    final s = AppStateScope.of(context);
    try {
      final updated = await s.api().pinMemory(
        userId: s.userId,
        memoryId: m.id,
        pinned: !m.pinned,
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final it in _items)
            if (it.id == m.id) updated else it,
        ]..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
          });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _delete(MemoryItemDto m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: Text(m.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = AppStateScope.of(context);
    try {
      await s.api().deleteMemoryItem(userId: s.userId, memoryId: m.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != m.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆本'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: '搜索记忆…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _reload();
                        },
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (key, label) = _categories[i];
                final selected = _category == key;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _category = key);
                    _reload();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(child: Text('暂无匹配的记忆'))
                        : RefreshIndicator(
                            onRefresh: _reload,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final m = _items[i];
                                return Material(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.fromLTRB(
                                      14,
                                      6,
                                      4,
                                      6,
                                    ),
                                    title: Text(m.text),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        [
                                          if (m.pinned) '置顶',
                                          MemoryItemDto.categoryLabel(
                                            m.category,
                                          ),
                                          if (m.factKey != null) m.factKey!,
                                        ].join(' · '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: m.pinned ? '取消置顶' : '置顶',
                                          icon: Icon(
                                            m.pinned
                                                ? Icons.push_pin
                                                : Icons.push_pin_outlined,
                                            size: 20,
                                            color: m.pinned
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : null,
                                          ),
                                          onPressed: () => _togglePin(m),
                                        ),
                                        IconButton(
                                          tooltip: '删除',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                          onPressed: () => _delete(m),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
