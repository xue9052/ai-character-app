import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'persona_cover.dart';

/// 对齐「创建形象」页：画风分类 + 描述 + 生成（走后端 image_gen）
class PersonaLookGenPage extends StatefulWidget {
  const PersonaLookGenPage({super.key, this.initialDescription = ''});

  final String initialDescription;

  @override
  State<PersonaLookGenPage> createState() => _PersonaLookGenPageState();
}

class _PersonaLookGenPageState extends State<PersonaLookGenPage> {
  static const _accent = AppColors.primary;
  static const _bg = AppColors.bgDark;
  static const _card = AppColors.bgDarkElevated;

  final _descCtrl = TextEditingController();
  List<String> _categories = const ['精选', '动漫', '可爱', '写实', '创意', '国风'];
  List<LookStyle> _styles = const [];
  String _category = '精选';
  String? _styleKey;
  bool _loadingStyles = true;
  bool _generating = false;
  bool _polishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _descCtrl.text = widget.initialDescription;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStyles());
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStyles() async {
    try {
      final payload = await AppStateScope.of(context).api().lookStyles();
      if (!mounted) return;
      setState(() {
        _categories = payload.categories.isNotEmpty
            ? payload.categories
            : _categories;
        _styles = payload.styles;
        _category = _categories.first;
        _styleKey = _filteredStyles.isNotEmpty ? _filteredStyles.first.key : null;
        _loadingStyles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStyles = false;
        _error = apiErrorMessage(e);
        // 本地兜底
        _styles = [
          LookStyle(key: 'manga_ii', name: '漫画 II', category: '精选', color: '#5B7C99', badge: 'New'),
          LookStyle(key: 'protagonist', name: '主角', category: '精选', color: '#8B6F5C'),
          LookStyle(key: 'nature', name: '质然', category: '精选', color: '#6B8F71'),
          LookStyle(key: 'classic', name: '经典', category: '精选', color: '#7A6B8F'),
          LookStyle(key: 'manga', name: '漫画', category: '动漫', color: '#4A7C8C'),
          LookStyle(key: 'yunmeng', name: '云梦泽', category: '国风', color: '#B87A8F', badge: 'New'),
        ];
        _styleKey = _styles.first.key;
      });
    }
  }

  List<LookStyle> get _filteredStyles => [
        for (final s in _styles)
          if (s.category == _category) s,
      ];

  Future<void> _polish() async {
    final s = AppStateScope.of(context);
    setState(() => _polishing = true);
    try {
      final text = await s.api().polishPersonaLookPrompt(
            userId: s.userId,
            description: _descCtrl.text,
            styleKey: _styleKey,
          );
      if (!mounted) return;
      setState(() => _descCtrl.text = text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  Future<void> _generate() async {
    if (_styleKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择画风')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final look = await s.api().generatePersonaLook(
            userId: s.userId,
            description: _descCtrl.text,
            styleKey: _styleKey,
          );
      if (!mounted) return;
      Navigator.of(context).pop(
        Uint8List.fromList(look.bytes),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(e));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStyles;
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _card,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: const Text('创建形象'),
          centerTitle: true,
        ),
        body: _loadingStyles
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '添加画风',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '画风适用于所有性别，部分画风不能同时使用',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF8A8A8A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: null,
                              child: Text(
                                '全部画风 >',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final c = _categories[i];
                              final on = c == _category;
                              return ChoiceChip(
                                label: Text(c),
                                selected: on,
                                onSelected: (_) => setState(() {
                                  _category = c;
                                  final list = [
                                    for (final s in _styles)
                                      if (s.category == c) s,
                                  ];
                                  _styleKey =
                                      list.isNotEmpty ? list.first.key : null;
                                }),
                                selectedColor: const Color(0xFF2A2A2A),
                                backgroundColor: Colors.transparent,
                                labelStyle: TextStyle(
                                  color: on
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.55),
                                  fontWeight:
                                      on ? FontWeight.w600 : FontWeight.w400,
                                ),
                                side: BorderSide(
                                  color: on
                                      ? Colors.white24
                                      : Colors.transparent,
                                ),
                                showCheckmark: false,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                          itemBuilder: (context, i) {
                            final s = filtered[i];
                            final selected = s.key == _styleKey;
                            return _StyleCard(
                              style: s,
                              selected: selected,
                              onTap: () => setState(() => _styleKey = s.key),
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          '形象描述',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Column(
                            children: [
                              TextField(
                                controller: _descCtrl,
                                maxLines: 5,
                                minLines: 4,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText:
                                      '(可选) 添加形象的详细描述，如五官、动作、服饰、背景等',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF6A6A6A),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _polishing ? null : _polish,
                                  icon: _polishing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _accent,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.auto_awesome,
                                          size: 16,
                                          color: _accent,
                                        ),
                                  label: const Text(
                                    '自动润色',
                                    style: TextStyle(
                                      color: _accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _generating ? null : _generate,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor:
                                _accent.withValues(alpha: 0.45),
                            shape: const StadiumBorder(),
                          ),
                          child: _generating
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.black87,
                                  ),
                                )
                              : const Text(
                                  '生成形象',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final LookStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : Colors.white12,
                  width: selected ? 2.2 : 1,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    parseHexColor(style.color),
                    parseHexColor(style.color).withValues(alpha: 0.55),
                    const Color(0xFF111111),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  if (style.badge.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          style.badge,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppColors.primaryLight
                  : Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
