import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../api/models.dart';
import '../../theme/app_theme.dart';
import 'persona_cover.dart';

/// 卡片底色 + 文字区蒙层色（固定，不再从图片取色）
const kPlazaCardBase = AppColors.bgDarkElevated;

/// 瀑布流列宽（双列 + 边距 + 间距）
double plazaWaterfallColumnWidth(BuildContext context, {double gap = 10}) {
  const horizontalPadding = 12.0;
  final w = MediaQuery.sizeOf(context).width;
  return (w - horizontalPadding * 2 - gap) / 2;
}

/// 懒加载瀑布流 Sliver（仅构建可见区域卡片）
Widget plazaWaterfallSliver({
  required List<PersonaSummary> items,
  required String baseUrl,
  required ValueChanged<PersonaSummary> onTap,
  double gap = 10,
}) {
  if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

  return SliverMasonryGrid.count(
    crossAxisCount: 2,
    mainAxisSpacing: gap,
    crossAxisSpacing: gap,
    childCount: items.length,
    itemBuilder: (context, index) {
      final p = items[index];
      return PlazaWaterfallCard(
        persona: p,
        width: plazaWaterfallColumnWidth(context, gap: gap),
        baseUrl: baseUrl,
        onTap: () => onTap(p),
      );
    },
  );
}

class PlazaWaterfallCard extends StatelessWidget {
  const PlazaWaterfallCard({
    super.key,
    required this.persona,
    required this.width,
    required this.baseUrl,
    required this.onTap,
  });

  final PersonaSummary persona;
  final double width;
  final String baseUrl;
  final VoidCallback onTap;

  static double _aspectFor(PersonaSummary p) {
    final h = p.id.hashCode.abs();
    return 0.88 + (h % 38) / 100.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = persona;
    final imageH = width * _aspectFor(p);
    final emoji = (p.coverEmoji != null && p.coverEmoji!.isNotEmpty)
        ? p.coverEmoji!
        : (p.name.isNotEmpty ? p.name.substring(0, 1) : '?');
    final coverUrl = resolvePersonaCoverUrl(baseUrl, p.coverUrl);
    final subtitle = (p.oneLiner ?? '').trim();
    const overlay = kPlazaCardBase;

    return Material(
      color: kPlazaCardBase,
      borderRadius: BorderRadius.circular(AppColors.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: imageH,
          width: width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                AppNetworkImage(
                  url: coverUrl,
                  fit: BoxFit.cover,
                  width: width,
                  height: imageH,
                  alignment: Alignment.topCenter,
                  memCacheWidth: (width * 2).round(),
                  placeholder: (_, __) => const ColoredBox(color: kPlazaCardBase),
                  errorWidget: (_, __, ___) => _coverFallback(emoji),
                )
              else
                _coverFallback(emoji),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        overlay.withValues(alpha: 0),
                        overlay.withValues(alpha: 0.35),
                        overlay.withValues(alpha: 0.82),
                        overlay.withValues(alpha: 0.96),
                      ],
                      stops: const [0.0, 0.38, 0.72, 1.0],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 32, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Color(0x66000000),
                              ),
                            ],
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12,
                              height: 1.35,
                              shadows: const [
                                Shadow(
                                  blurRadius: 6,
                                  color: Color(0x55000000),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback(String emoji) {
    return ColoredBox(
      color: kPlazaCardBase,
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(
            fontSize: 42,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
