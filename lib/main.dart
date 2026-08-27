import 'package:flutter/material.dart';
import 'package:flutter_ai_ui_kit/flutter_ai_ui_kit.dart';

import 'app.dart';
import 'features/auth/login_page.dart';
import 'services/app_state.dart';
import 'services/dev_flags.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DevFlags.load();
  final state = await AppState.load();
  runApp(AiCharacterApp(state: state));
}

class AiCharacterApp extends StatelessWidget {
  const AiCharacterApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: state,
      child: AiUiThemeScope(
        data: AiUiThemeData.dark().copyWith(
          accentColor: AppColors.primary,
          accentSecondary: AppColors.primaryLight,
          userBubbleColor: AppColors.primary,
          userBubbleGradient: AppColors.primaryGradient,
          assistantBubbleColor: AppColors.bgDarkElevated,
          backgroundColor: AppColors.bgDark,
          surfaceColor: AppColors.bgDarkElevated,
          typingDotColor: AppColors.accentCyan,
          accentGradient: AppColors.primaryGradient,
          bubbleRadius: AppColors.radiusBubble,
          inputBackgroundColor: AppColors.bgDarkElevated,
          inputFocusBorderColor: AppColors.primary,
        ),
        child: MaterialApp(
          title: 'AI 虚拟角色',
          debugShowCheckedModeBanner: false,
          theme: buildAppLightTheme(),
          darkTheme: buildAppDarkTheme(),
          themeMode: ThemeMode.dark,
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (s.isLoggedIn) return const AppRoot();
        return const LoginPage();
      },
    );
  }
}
