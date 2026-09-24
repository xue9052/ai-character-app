import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 沉浸式聊天顶栏：磨砂 + 渐变遮罩，避免消息滚入后盖住标题。
class ChatTopBar extends StatelessWidget {
  const ChatTopBar({
    super.key,
    required this.topInset,
    required this.child,
    this.showProgress = false,
  });

  final double topInset;
  final Widget child;
  final bool showProgress;

  /// 消息列表顶部留白（状态栏 + 顶栏内容 + 渐变过渡）。
  static double listTopPadding(
    double topInset, {
    bool showProgress = false,
  }) {
    return topInset + (showProgress ? 78.0 : 64.0);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.bgDark.withValues(alpha: 0.68),
                  AppColors.bgDark.withValues(alpha: 0.48),
                  AppColors.bgDark.withValues(alpha: 0.22),
                  AppColors.bgDark.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.42, 0.72, 1.0],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, topInset + 4, 8, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showProgress)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
