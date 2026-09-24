import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import 'persona_cover.dart';
import 'persona_detail_page.dart';
import 'persona_presets.dart';

/// 广场搜索页：按名字、简介或标签搜索公开角色
class PersonaSearchPage extends StatefulWidget {
  const PersonaSearchPage({super.key});

  @override
  State<PersonaSearchPage> createState() => _PersonaSearchPageState();
}

class _PersonaSearchPageState extends State<PersonaSearchPage> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  List<String> _tagPresets = kPersonaTagPresets;
  String? _selectedTag;
  List<PersonaSummary> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _runSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.removeListener(_onQueryChanged);
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _runSearch);
  }

  Future<void> _runSearch() async {
    final s = AppStateScope.of(context);
    final q = _queryCtrl.text.trim();
    final tag = _selectedTag;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await s.api().searchPersonas(
            s.userId,
            q: q,
            tag: tag,
          );
      if (!mounted) return;
      setState(() {
        if (res.tagPresets.isNotEmpty) _tagPresets = res.tagPresets;
        _items = res.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectTag(String? tag) {
    if (_selectedTag == tag) return;
    setState(() => _selectedTag = tag);
    _runSearch();
  }

  void _clearQuery() {
    _queryCtrl.clear();
    _debounce?.cancel();
    _runSearch();
  }

  Future<void> _openDetail(PersonaSummary p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PersonaDetailPage(personaId: p.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 44,
          leading: Center(
            child: FrostIconButton(
              icon: Icons.arrow_back_rounded,
              size: 32,
              iconSize: 18,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          title: _buildSearchField(),
          titleSpacing: 0,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTagChips(),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: TextField(
        controller: _queryCtrl,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          _debounce?.cancel();
          _runSearch();
        },
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        decoration: frostInputDecoration(
          hintText: '搜索角色名、简介或标签',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textMuted,
          ),
          suffixIcon: _queryCtrl.text.isNotEmpty
              ? IconButton(
                  tooltip: '清空',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textMuted,
                  ),
                  onPressed: _clearQuery,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          _tagChip(label: '全部', tag: null),
          for (final t in _tagPresets) _tagChip(label: t, tag: t),
        ],
      ),
    );
  }

  Widget _tagChip({required String label, required String? tag}) {
    final active = _selectedTag == tag;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => _selectTag(tag),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 13,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.65),
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
        backgroundColor: AppColors.glassSmoke,
        selectedColor: AppColors.glassLight,
        side: BorderSide(
          color: active ? AppColors.strokeStrong : AppColors.strokeSoft,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildResults() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      );
    }

    if (_error != null && _items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primaryLight,
        onRefresh: _runSearch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '搜索失败：$_error\n下拉重试',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      final q = _queryCtrl.text.trim();
      final hint = q.isNotEmpty || _selectedTag != null
          ? '没有找到匹配的角色\n试试换个关键词或标签'
          : '输入名字或选择标签开始搜索';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.search_off_rounded,
              size: 48, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          ),
        ],
      );
    }

    final baseUrl = AppStateScope.of(context).baseUrl;
    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: _runSearch,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _SearchResultTile(
          persona: _items[i],
          baseUrl: baseUrl,
          onTap: () => _openDetail(_items[i]),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.persona,
    required this.baseUrl,
    required this.onTap,
  });

  final PersonaSummary persona;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final liner = (p.oneLiner ?? '').trim();
    final tags = p.tags.take(3).toList(growable: false);

    return Material(
      color: AppColors.glassSmoke,
      borderRadius: BorderRadius.circular(AppColors.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonaCoverAvatar(
                baseUrl: baseUrl,
                coverUrl: p.coverUrl,
                fallbackColor: parseHexColor(p.coverColor ?? '#7B6CF6'),
                fallbackLabel: (p.coverEmoji != null && p.coverEmoji!.isNotEmpty)
                    ? p.coverEmoji!
                    : (p.name.isNotEmpty ? p.name.substring(0, 1) : '?'),
                radius: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (liner.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        liner,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final t in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
