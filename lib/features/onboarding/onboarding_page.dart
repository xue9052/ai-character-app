import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';

/// 注册后偏好引导：选陪伴对象 + 可选昵称
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  OnboardingConfig? _config;
  bool _loading = true;
  String? _error;
  int _step = 0;
  String _preference = 'female';
  final _nicknameCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = AppStateScope.of(context);
      if (!s.isLoggedIn) {
        throw StateError('请先登录');
      }
      final cfg = await s.api().onboardingConfig();
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _preference = cfg.companionPreference;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish({bool skipNickname = false}) async {
    if (_submitting) return;
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) return;
    setState(() => _submitting = true);
    try {
      var user = await s.api().updatePreferences(
        accessToken: token,
        companionPreference: _preference,
        onboardingCompleted: true,
      );
      final nick = _nicknameCtrl.text.trim();
      if (!skipNickname && nick.isNotEmpty) {
        user = await s.api().updateMe(
          accessToken: token,
          nickname: nick,
        );
      }
      await s.applyUser(user);
      if (!mounted) return;
      widget.onFinished();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryLight),
                )
              : _error != null
                  ? _ErrorBody(message: _error!, onRetry: _load)
                  : _step == 0
                      ? _PreferenceStep(
                          config: _config!,
                          selected: _preference,
                          submitting: _submitting,
                          onSelect: (v) => setState(() => _preference = v),
                          onNext: () => setState(() => _step = 1),
                          onSkip: () => unawaited(_finish(skipNickname: true)),
                        )
                      : _NicknameStep(
                          config: _config!,
                          controller: _nicknameCtrl,
                          submitting: _submitting,
                          onDone: () => unawaited(_finish()),
                          onSkip: () => unawaited(_finish(skipNickname: true)),
                        ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FrostButton(expanded: false, onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _PreferenceStep extends StatelessWidget {
  const _PreferenceStep({
    required this.config,
    required this.selected,
    required this.submitting,
    required this.onSelect,
    required this.onNext,
    required this.onSkip,
  });

  final OnboardingConfig config;
  final String selected;
  final bool submitting;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final options = config.options.isNotEmpty
        ? config.options
        : [
            OnboardingOption(value: 'female', label: '女生角色', hint: '想听她说'),
            OnboardingOption(value: 'male', label: '男生角色', hint: '想听他说'),
            OnboardingOption(value: 'any', label: '都可以', hint: '混合推荐'),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            config.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            config.subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.55),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OptionTile(
                        label: o.label,
                        hint: o.hint,
                        selected: selected == o.value,
                        onTap: () => onSelect(o.value),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FrostButton(
            onPressed: submitting ? null : onNext,
            child: submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('下一步'),
          ),
          TextButton(
            onPressed: submitting ? null : onSkip,
            child: Text(
              '跳过，先看精选',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NicknameStep extends StatelessWidget {
  const _NicknameStep({
    required this.config,
    required this.controller,
    required this.submitting,
    required this.onDone,
    required this.onSkip,
  });

  final OnboardingConfig config;
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            config.nicknameTitle,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            config.nicknameSubtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: controller,
            maxLength: 24,
            style: const TextStyle(color: Colors.white),
            decoration: frostInputDecoration(hintText: '例如：阿杰'),
          ),
          const Spacer(),
          FrostButton(
            onPressed: submitting ? null : onDone,
            child: submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('进入精选'),
          ),
          TextButton(
            onPressed: submitting ? null : onSkip,
            child: Text(
              '跳过',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.glassLight : AppColors.glassSmoke,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.strokeStrong : AppColors.strokeSoft,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (hint.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}