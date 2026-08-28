import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_page.dart';
import 'persona_presets.dart';
import 'persona_editor_page.dart';
import 'persona_search_page.dart';
import 'plaza_waterfall_grid.dart';

/// 角色广场 — 顶栏 Tab + 左右滑动切换 + 双列瀑布流
class PersonaListPage extends StatefulWidget {
  const PersonaListPage({super.key});

  @override
  State<PersonaListPage> createState() => _PersonaListPageState();
}

class _PersonaListPageState extends State<PersonaListPage> {
  final PageController _pageController = PageController();
  final ScrollController _tabScrollController = ScrollController();

  List<String> _tagPresets = kPersonaTagPresets;
  final Map<String?, List<PersonaSummary>> _gridCache = {};
  final Map<String?, String?> _errorCache = {};
  final Set<String?> _loadingTags = {};

  bool _initialLoading = true;
  String? _error;
  String? _tag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoading && _gridCache.isEmpty && _error == null) {
      _loadTag(null, initial: true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  List<String> get _tabs => ['推荐', ..._tagPresets];

  String? _tagForTabIndex(int i) => i == 0 ? null : _tagPresets[i - 1];

  int _indexForTag(String? tag) {
    if (tag == null) return 0;
    final idx = _tagPresets.indexOf(tag);
    return idx < 0 ? 0 : idx + 1;
  }

  int get _selectedTabIndex => _indexForTag(_tag);

  Future<void> _loadTag(String? tag, {bool initial = false}) async {
    if (!initial && _gridCache.containsKey(tag)) {
      if (mounted) setState(() => _tag = tag);
      return;
    }
    if (_loadingTags.contains(tag)) return;

    final s = AppStateScope.of(context);
    final api = s.api();
    if (mounted) {
      setState(() {
        _loadingTags.add(tag);
        if (initial) {
          _initialLoading = true;
          _error = null;
        }
        _tag = tag;
      });
    }

    try {
      final feed = await api.listPlaza(s.userId, tag: tag);
      if (!mounted) return;
      setState(() {
        if (feed.tagPresets.isNotEmpty) {
          _tagPresets = feed.tagPresets;
        }
        _gridCache[tag] = feed.grid;
        _errorCache[tag] = null;
        _loadingTags.remove(tag);
        _initialLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCache[tag] = '$e';
        _loadingTags.remove(tag);
        _initialLoading = false;
        if (initial) _error = '$e';
      });
    }
  }

  Future<void> _reloadTag(String? tag) => _loadTag(tag, initial: true);

  Future<void> _reloadCurrent() => _reloadTag(_tag);

  void _selectTabIndex(int index, {bool fromSwipe = false}) {
    final tag = _tagForTabIndex(index);
    if (!fromSwipe) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    _scrollTabIntoView(index);
    _loadTag(tag);
  }

  void _scrollTabIntoView(int index) {
    if (!_tabScrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tabScrollController.hasClients) return;
      const estTabWidth = 52.0;
      final target = (index * estTabWidth - 40)
          .clamp(0.0, _tabScrollController.position.maxScrollExtent);
      _tabScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PersonaSearchPage()),
    );
  }

  Future<void> _openCreate() async {
    final saved = await Navigator.of(context).push<PersonaDetail>(
      MaterialPageRoute(builder: (_) => const PersonaEditorPage()),
    );
    if (!mounted) return;
    if (saved != null) {
      _gridCache.clear();
      _errorCache.clear();
      await _reloadCurrent();
      if (!mounted) return;
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

  Future<void> _openChat(PersonaSummary p) async {
    final s = AppStateScope.of(context);
    await s.setLastPersona(p.id);
    if (!mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppDarkTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E14),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(child: _buildPager()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            tooltip: '创建角色',
            onPressed: _openCreate,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: Colors.white70,
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final selected = _selectedTabIndex;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        itemCount: _tabs.length,
        itemBuilder: (context, i) {
          final active = i == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () => _selectTabIndex(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _tabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 2,
                      width: active ? 18 : 0,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPager() {
    if (_initialLoading && _gridCache.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _tabs.length,
      onPageChanged: (index) {
        setState(() => _tag = _tagForTabIndex(index));
        _scrollTabIntoView(index);
        _loadTag(_tag);
      },
      itemBuilder: (context, index) {
        return _buildTabPage(_tagForTabIndex(index));
      },
    );
  }

  Widget _buildTabPage(String? tag) {
    final loading = _loadingTags.contains(tag);
    final err = _errorCache[tag];
    final items = _gridCache[tag];
    final baseUrl = AppStateScope.of(context).baseUrl;

    if (loading && items == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      );
    }

    if (err != null && items == null) {
      return RefreshIndicator(
        color: AppColors.primaryLight,
        onRefresh: () => _reloadTag(tag),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '加载失败：$err\n下拉刷新，或检查网络',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          ],
        ),
      );
    }

    final gridItems = items ?? const <PersonaSummary>[];

    if (gridItems.isEmpty && !loading) {
      return RefreshIndicator(
        color: AppColors.primaryLight,
        onRefresh: () => _reloadTag(tag),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 64),
            Icon(
              Icons.explore_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              tag == null ? '广场暂无可发现的角色' : '该标签下暂无角色',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: () => _reloadTag(tag),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          if (loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 12, top: 8),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            sliver: plazaWaterfallSliver(
              items: gridItems,
              baseUrl: baseUrl,
              onTap: _openChat,
            ),
          ),
        ],
      ),
    );
  }
}
