import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

enum FrostTone { light, soft, smoke }

Color _toneColor(FrostTone tone) {
  switch (tone) {
    case FrostTone.light:
      return AppColors.glassLight;
    case FrostTone.soft:
      return AppColors.glassSoft;
    case FrostTone.smoke:
      return AppColors.glassSmoke;
  }
}

/// 毛玻璃面板：卡片、弹层、分组底。
class FrostSurface extends StatelessWidget {
  const FrostSurface({
    super.key,
    required this.child,
    this.tone = FrostTone.smoke,
    this.padding,
    this.radius = AppColors.radiusCard,
    this.blur = 22,
    this.borderColor,
  });

  final Widget child;
  final FrostTone tone;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _toneColor(tone),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ??
                  (tone == FrostTone.light
                      ? AppColors.strokeStrong
                      : AppColors.strokeSoft),
            ),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

/// 主操作：浅白玻璃胶囊 + 白字。
class FrostButton extends StatelessWidget {
  const FrostButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 50,
    this.expanded = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppColors.radiusButton),
          child: FrostSurface(
            tone: FrostTone.light,
            radius: AppColors.radiusButton,
            blur: 20,
            child: SizedBox(
              height: height,
              child: Center(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 顶栏 / 输入条圆钮，与聊天页一致。
class FrostIconButton extends StatelessWidget {
  const FrostIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = AppColors.iconButtonSize,
    this.iconSize = 18,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: highlighted ? AppColors.glassLight : AppColors.glassSoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: AppColors.textPrimary),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}

InputDecoration frostInputDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  EdgeInsetsGeometry? contentPadding,
}) {
  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppColors.glassSoft,
    hintStyle: const TextStyle(color: AppColors.textMuted),
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusPill),
      borderSide: const BorderSide(color: AppColors.strokeSoft),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusPill),
      borderSide: const BorderSide(color: AppColors.strokeSoft),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusPill),
      borderSide: const BorderSide(color: AppColors.strokeStrong, width: 1.4),
    ),
  );
}

/// 胶囊输入框。
class FrostField extends StatelessWidget {
  const FrostField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      autofillHints: autofillHints,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      cursorColor: AppColors.textPrimary,
      decoration: frostInputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// 兼容旧名：主按钮改为浅白玻璃。
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 50,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FrostButton(onPressed: onPressed, height: height, child: child);
  }
}

/// 兼容旧名：走毛玻璃面。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppColors.radiusCard,
    this.light = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return FrostSurface(
      tone: light ? FrostTone.soft : FrostTone.smoke,
      padding: padding,
      radius: radius,
      child: child,
    );
  }
}

class SouloraMark extends StatelessWidget {
  const SouloraMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        AppBrand.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

class FrostNavItem {
  const FrostNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 底栏：毛玻璃条 + 选中变亮，不用 Material 滑动胶囊。
class FrostNavBar extends StatelessWidget {
  const FrostNavBar({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
  });

  final int index;
  final List<FrostNavItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.strokeSoft)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            color: const Color(0x99101014),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 6 + bottom),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _FrostNavButton(
                        item: items[i],
                        selected: i == index,
                        onTap: () => onChanged(i),
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

class _FrostNavButton extends StatelessWidget {
  const _FrostNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FrostNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      splashColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.0 : 0.92,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 24,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
