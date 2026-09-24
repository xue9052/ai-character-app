import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_ai_ui_kit/flutter_ai_ui_kit.dart';

import 'features/onboarding/onboarding_page.dart';
import 'app.dart';
import 'features/auth/login_page.dart';
import 'features/settings/edit_profile_page.dart';
import 'services/app_state.dart';
import 'services/dev_flags.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DevFlags.load();
  final state = await AppState.load();
  runApp(AiCharacterApp(state: state));
  if (state.isLoggedIn) {
    unawaited(state.refreshSessionFromServer());
  }
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
          accentColor: AppColors.glassLight,
          accentSecondary: AppColors.textSecondary,
          userBubbleColor: AppColors.glassLight,
          userBubbleGradient: AppColors.primaryGradient,
          assistantBubbleColor: AppColors.glassSmoke,
          backgroundColor: AppColors.bgDark,
          surfaceColor: AppColors.bgDarkElevated,
          typingDotColor: AppColors.textSecondary,
          accentGradient: AppColors.primaryGradient,
          bubbleRadius: AppColors.radiusBubble,
          inputBackgroundColor: AppColors.glassSoft,
          inputFocusBorderColor: AppColors.strokeStrong,
        ),
        child: MaterialApp(
          title: AppBrand.name,
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

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Key _onboardingKey = UniqueKey();

  void _onOnboardingFinished() {
    setState(() => _onboardingKey = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (!s.isLoggedIn) return const LoginPage();
        final user = s.user;
        // 注册后先完善资料，再进偏好引导
        if (user != null && !user.profileCompleted) {
          return EditProfilePage(
            key: ValueKey('profile-${user.id}'),
            fromRegister: true,
          );
        }
        if (user != null && !user.onboardingCompleted) {
          return OnboardingPage(
            key: _onboardingKey,
            onFinished: _onOnboardingFinished,
          );
        }
        return const AppRoot();
      },
    );
  }
}
