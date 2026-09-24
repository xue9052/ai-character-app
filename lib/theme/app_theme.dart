import 'package:flutter/material.dart';

/// 全站主题：跟聊天页同一套浅白 / 烟灰毛玻璃，不再用紫色填色。
abstract final class AppBrand {
  static const name = 'Soulora';
  static const tagline = '你的专属陪伴';
  static const logoAsset = 'assets/images/soulora_logo.png';
}

abstract final class AppColors {
  static const glassLight = Color(0x8FFFFFFF);
  static const glassSoft = Color(0x40FFFFFF);
  static const glassSmoke = Color(0x73383840);
  static const strokeStrong = Color(0x85FFFFFF);
  static const strokeSoft = Color(0x2EFFFFFF);

  static const bgDark = Color(0xFF0E0E14);
  static const bgDarkElevated = Color(0xFF1C1C22);
  static const bgLight = Color(0xFFF4F4F6);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xB8FFFFFF);
  static const textMuted = Color(0x73FFFFFF);

  /// 兼容旧引用：不再当品牌紫，只当浅白点缀。
  static const primary = Color(0xFFFFFFFF);
  static const primaryLight = Color(0xE6FFFFFF);

  static const accentPink = Color(0xFFFF8A9B);
  static const accentCyan = Color(0xFF5CE1E6);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFB923C);

  static const radiusCard = 24.0;
  static const radiusButton = 28.0;
  static const radiusBubble = 24.0;
  static const radiusPill = 30.0;
  static const iconButtonSize = 40.0;

  static const primaryGradient = LinearGradient(
    colors: [Color(0x8FFFFFFF), Color(0x59FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const bondGradient = LinearGradient(
    colors: [accentPink, Color(0xFFFFB4C0)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const nightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF16161C),
      bgDark,
      Color(0xFF0A0A0E),
    ],
  );
}

OutlineInputBorder _frostBorder({Color? color, double width = 1.2}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusPill),
    borderSide: BorderSide(
      color: color ?? AppColors.strokeSoft,
      width: width,
    ),
  );
}

ThemeData buildAppDarkTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB8B8C0),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: base.copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accentPink,
      tertiary: AppColors.accentCyan,
      surface: AppColors.bgDarkElevated,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.warning,
    ),
    scaffoldBackgroundColor: AppColors.bgDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.glassSmoke,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        side: const BorderSide(color: AppColors.strokeSoft),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.glassSmoke,
      selectedColor: AppColors.glassLight,
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      secondaryLabelStyle: const TextStyle(color: AppColors.textPrimary),
      side: const BorderSide(color: AppColors.strokeSoft),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.glassSoft,
      border: _frostBorder(),
      enabledBorder: _frostBorder(),
      focusedBorder: _frostBorder(color: AppColors.strokeStrong, width: 1.4),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.glassLight,
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusButton),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.strokeStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusButton),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.glassLight,
      foregroundColor: AppColors.textPrimary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xCC101014),
      indicatorColor: AppColors.glassSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.textPrimary : AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.textPrimary : AppColors.textMuted,
        );
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.strokeSoft),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
    ),
  );
}

ThemeData buildAppLightTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB8B8C0),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: base.copyWith(
      primary: const Color(0xFF2A2A30),
      secondary: AppColors.accentPink,
      tertiary: AppColors.accentCyan,
      surface: Colors.white,
      onSurface: const Color(0xFF1A1A1E),
      onSurfaceVariant: const Color(0xFF6A6A74),
    ),
    scaffoldBackgroundColor: AppColors.bgLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Color(0xFF1A1A1E),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        side: const BorderSide(color: Color(0x14000000)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.85),
      border: _frostBorder(color: const Color(0x22000000)),
      focusedBorder: _frostBorder(color: const Color(0x66000000), width: 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2A2A30),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusButton),
        ),
      ),
    ),
  );
}
