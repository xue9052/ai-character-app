import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/app_theme.dart';

/// 审核状态角标：待审 / 已通过 / 已驳回
class ReviewBadge extends StatelessWidget {
  const ReviewBadge({super.key, required this.status, this.compact = false});

  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = (status ?? 'approved').toLowerCase();
    final String label;
    final Color fg;
    final Color bg;
    if (s == 'pending') {
      label = compact ? '待审' : '审核中';
      fg = AppColors.warning;
      bg = AppColors.warning.withValues(alpha: 0.18);
    } else if (s == 'rejected') {
      label = compact ? '驳回' : '未通过';
      fg = Theme.of(context).colorScheme.error;
      bg = Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.55);
    } else {
      label = compact ? '通过' : '已通过';
      fg = AppColors.success;
      bg = AppColors.success.withValues(alpha: 0.16);
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
      ),
    );
  }
}

String reviewHint(PersonaSummary p) {
  if (p.isPrivate) {
    return '仅自己可见，不会出现在广场';
  }
  if (p.isPending) return '公开审核中：通过后其他用户才能在广场看到';
  if (p.isRejected) {
    final r = p.reviewReason?.trim();
    return (r != null && r.isNotEmpty) ? '未通过：$r' : '未通过审核，修改后将重新提交';
  }
  return '公开已通过，其他用户可在广场看到';
}
