import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 今日 AI 场景图剩余次数角标。
class SceneQuotaBadge extends StatelessWidget {
  const SceneQuotaBadge({
    super.key,
    this.remaining,
    this.limit,
    this.compact = false,
  });

  final int? remaining;
  final int? limit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (remaining == null || limit == null || limit! <= 0) {
      return const SizedBox.shrink();
    }
    final rem = remaining!.clamp(0, limit!);
    final label = compact ? '$rem/$limit' : '场景图 $rem/$limit';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: rem > 0
            ? AppColors.accentPink.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: rem > 0
              ? AppColors.accentPink.withValues(alpha: 0.45)
              : AppColors.strokeSoft,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: rem > 0 ? AppColors.accentPink : AppColors.textSecondary,
        ),
      ),
    );
  }
}
