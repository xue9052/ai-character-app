import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 聊天气泡内的「语音」播放条。
class VoicePlayChip extends StatelessWidget {
  const VoicePlayChip({
    super.key,
    required this.playing,
    required this.loading,
    required this.onTap,
    this.label = '语音',
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.strokeSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              Icon(
                playing ? Icons.volume_up_rounded : Icons.graphic_eq_rounded,
                size: 16,
                color: AppColors.accentPink,
              ),
            const SizedBox(width: 6),
            Text(
              loading ? '加载中' : (playing ? '播放中' : label),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
