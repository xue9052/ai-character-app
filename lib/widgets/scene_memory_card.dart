import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_network_image.dart';

/// 场景记忆卡（单聊 / 群聊共用样式）。
class SceneMemoryCard extends StatelessWidget {
  const SceneMemoryCard({
    super.key,
    required this.title,
    this.summary = '',
    this.imageUrl = '',
    this.httpHeaders,
    this.onOpenImage,
  });

  final String title;
  final String summary;
  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final void Function(String url)? onOpenImage;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.trim().isNotEmpty
        ? title.trim()
        : '记住了这一刻';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accentPink.withValues(alpha: 0.18),
              AppColors.glassSmoke,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.strokeSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.push_pin_outlined,
                    size: 16,
                    color: AppColors.accentPink,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (imageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                _image(),
              ],
              if (summary.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  summary.trim(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _image() {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AppNetworkImage(
        url: imageUrl,
        width: double.infinity,
        height: 140,
        fit: BoxFit.cover,
        httpHeaders: httpHeaders,
      ),
    );
    if (onOpenImage == null) return image;
    return GestureDetector(
      onTap: () => onOpenImage!(imageUrl),
      child: image,
    );
  }
}
