import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 酸话气泡下的送花入口，点击走 /v1/groups/{id}/resolve 化解
class ResolveBar extends StatelessWidget {
  const ResolveBar({
    super.key,
    required this.personaName,
    this.onTap,
    this.stardustLabel = '一束花',
  });

  final String personaName;
  final VoidCallback? onTap;
  final String stardustLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 16, bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.glassSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.strokeSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_florist_outlined,
                    size: 16,
                    color: AppColors.accentPink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '哄哄$personaName · $stardustLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
