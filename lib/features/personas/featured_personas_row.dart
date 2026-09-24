import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_network_image.dart';
import 'persona_cover.dart';

/// 官方精选：竖版封面横滑卡（对齐示意）
class FeaturedPersonasRow extends StatelessWidget {
  const FeaturedPersonasRow({
    super.key,
    required this.items,
    required this.onTap,
    required this.onChat,
  });

  final List<PersonaSummary> items;
  final void Function(PersonaSummary) onTap;
  final void Function(PersonaSummary) onChat;

  Color _coverBg(PersonaSummary p) {
    final hex = (p.coverColor ?? '#7B6CF6').replaceFirst('#', '');
    try {
      return Color(int.parse(hex, radix: 16) + 0xFF000000);
    } catch (_) {
      return AppColors.primary;
    }
  }

  String? _displayTag(PersonaSummary p) {
    const skip = {'男向', '语音陪伴', '测试'};
    for (final t in p.tags) {
      final tag = t.trim();
      if (tag.isNotEmpty && !skip.contains(tag)) return tag;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final baseUrl = AppStateScope.of(context).baseUrl;
    return SizedBox(
      height: 236,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = items[i];
          final emoji = (p.coverEmoji != null && p.coverEmoji!.isNotEmpty)
              ? p.coverEmoji!
              : (p.name.isNotEmpty ? p.name.substring(0, 1) : '?');
          final cover = resolvePersonaCoverUrl(baseUrl, p.coverUrl);
          final tag = _displayTag(p);
          return SizedBox(
            width: 148,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(p),
                onLongPress: () => onChat(p),
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          AppNetworkImage(
                            url: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => ColoredBox(
                              color: _coverBg(p),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 40,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          ColoredBox(
                            color: _coverBg(p),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                ),
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Color(0x99000000),
                                Color(0xE6000000),
                              ],
                              stops: [0, 0.42, 0.72, 1],
                            ),
                          ),
                        ),
                        if (tag != null)
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.oneLiner?.isNotEmpty == true ? p.oneLiner! : '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
