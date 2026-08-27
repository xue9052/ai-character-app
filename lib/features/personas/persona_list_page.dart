import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_page.dart';
import 'featured_personas_row.dart';
import 'persona_presets.dart';
import 'persona_workshop_page.dart';
import 'persona_cover.dart';

/// 角色广场 — 浅紫示意：精选横滑 + 标签 + 双列卡
class PersonaListPage extends StatefulWidget {
  const PersonaListPage({super.key});

  @override
  State<PersonaListPage> createState() => _PersonaListPageState();
}

class _PersonaListPageState extends State<PersonaListPage> {
  List<PersonaSummary> _strip = const [];
  List<String> _tagPresets = kPersonaTagPresets;
  Future<List<PersonaSummary>>? _gridFuture;
  bool _loading = true;
  String? _error;
  String? _tag;
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gridFuture == null) {
      _loadPlaza(initial: true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlaza({bool initial = false}) async {
    final s = AppStateScope.of(context);
    final api = ApiClient(s.baseUrl);
    if (mounted) {
      setState(() {
        _loading = initial && _strip.isEmpty;
        _error = null;
      });
    }
    try {
      final feed = await api.listPlaza(s.userId, tag: _tag);
      if (!mounted) return;
      setState(() {
        if (initial || _tag == null) {
          _strip = feed.strip;
          if (feed.tagPresets.isNotEmpty) {
            _tagPresets = feed.tagPresets;
          }
        }
        _gridFuture = Future.value(feed.grid);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reloadGridOnly() async {
    final s = AppStateScope.of(context);
    final next = ApiClient(s.baseUrl).listPlazaGrid(s.userId, tag: _tag);
    setState(() => _gridFuture = next);
    await next;
  }

  Future<void> _reload() => _loadPlaza(initial: true);

  void _setTag(String? tag) {
    if (_tag == tag) return;
    setState(() => _tag = tag);
    _reloadGridOnly();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _searchQuery = '';
      }
    });
  }

  void _onSearchChanged(String q) {
    setState(() => _searchQuery = q.trim());
  }

  List<PersonaSummary> _filterByName(List<PersonaSummary> items, String q) {
    if (q.isEmpty) return items;
    final lower = q.toLowerCase();
    return items
        .where((p) => p.name.toLowerCase().contains(lower))
        .toList();
  }

  Future<void> _openWorkshop() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PersonaWorkshopPage()),
    );
    if (mounted) _reload();
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

  Color _coverBg(PersonaSummary p) {
    final hex = (p.coverColor ?? kCoverColors.first).replaceFirst('#', '');
    try {
      return Color(int.parse(hex, radix: 16) + 0xFF000000);
    } catch (_) {
      return AppColors.primary;
    }
  }

  Widget _tagChip(String label, {required bool selected, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AppColors.primary : const Color(0xFFEDE8FA),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppLightTheme(),
      child: Scaffold(
        backgroundColor: AppColors.bgLight,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: _searchOpen
                    ? Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: '按角色名称搜索',
                                filled: true,
                                fillColor: const Color(0xFFEDE8FA),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: AppColors.primary,
                                ),
                                suffixIcon: _searchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          _onSearchChanged('');
                                        },
                                        icon: const Icon(Icons.clear_rounded),
                                      ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _toggleSearch,
                            child: const Text('取消'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Text(
                            '角色广场',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '我的角色',
                            onPressed: _openWorkshop,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          IconButton(
                            tooltip: '搜索',
                            onPressed: _toggleSearch,
                            icon: const Icon(Icons.search_rounded),
                            color: AppColors.textPrimary,
                          ),
                        ],
                      ),
              ),
              Expanded(
                child: _buildPlazaBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlazaBody() {
    if (_loading && _strip.isEmpty && _gridFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _strip.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '加载失败：$_error\n下拉刷新，或检查 API 地址',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final searching = _searchOpen && _searchQuery.isNotEmpty;
    final baseUrl = AppStateScope.of(context).baseUrl;
    final strip = searching ? const <PersonaSummary>[] : _strip;

    return FutureBuilder<List<PersonaSummary>>(
      future: _gridFuture,
      builder: (context, snap) {
        final gridRaw = snap.data ?? const <PersonaSummary>[];
        final sourceGrid = searching
            ? <PersonaSummary>[
                ...{
                  for (final p in [..._strip, ...gridRaw]) p.id: p,
                }.values,
              ]
            : gridRaw;
        final gridItems = _filterByName(sourceGrid, _searchQuery);
        final gridLoading =
            snap.connectionState != ConnectionState.done && gridItems.isEmpty;

        if (searching && gridItems.isEmpty && !gridLoading) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                '没有找到「$_searchQuery」',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          );
        }

        if (strip.isEmpty && gridItems.isEmpty && !gridLoading) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 64),
                Icon(
                  Icons.explore_outlined,
                  size: 48,
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 12),
                Text(
                  _tag == null ? '广场暂无可发现的角色' : '该标签下暂无热门角色',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (strip.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 14),
                    child: FeaturedPersonasRow(
                      items: strip,
                      onTap: _openChat,
                      onChat: _openChat,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _tagChip(
                        '最热',
                        selected: _tag == null,
                        onTap: () => _setTag(null),
                      ),
                      for (final t in _tagPresets)
                        _tagChip(
                          t,
                          selected: _tag == t,
                          onTap: () => _setTag(_tag == t ? null : t),
                        ),
                    ],
                  ),
                ),
              ),
              if (gridLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final p = gridItems[i];
                        return _PlazaGridCard(
                          persona: p,
                          coverColor: _coverBg(p),
                          baseUrl: baseUrl,
                          onTap: () => _openChat(p),
                        );
                      },
                      childCount: gridItems.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlazaGridCard extends StatelessWidget {
  const _PlazaGridCard({
    required this.persona,
    required this.coverColor,
    required this.baseUrl,
    required this.onTap,
  });

  final PersonaSummary persona;
  final Color coverColor;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final emoji = (p.coverEmoji != null && p.coverEmoji!.isNotEmpty)
        ? p.coverEmoji!
        : (p.name.isNotEmpty ? p.name.substring(0, 1) : '?');

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      shadowColor: AppColors.primary.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                ),
                child: SizedBox(
                  width: 78,
                  child: ColoredBox(
                    color: coverColor,
                    child: Builder(
                      builder: (context) {
                        final url = resolvePersonaCoverUrl(baseUrl, p.coverUrl);
                        if (url != null) {
                          return AppNetworkImage(
                            url: url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            alignment: Alignment.center,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          );
                        }
                        return Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if ((p.oneLiner ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          p.oneLiner!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
