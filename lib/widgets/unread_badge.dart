import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 会话/群聊未读角标（数字，超过 99 显示 99+）。
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    final wide = label.length > 1;
    return Container(
      constraints: BoxConstraints(
        minWidth: wide ? 20 : 18,
        minHeight: 18,
      ),
      padding: EdgeInsets.symmetric(horizontal: wide ? 5 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentPink,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.bgDark, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
