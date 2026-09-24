import 'dart:async';

import 'package:flutter/material.dart';

/// 验证码按钮 60s 冷却（发送成功后调用）。
mixin EmailCodeCooldown<T extends StatefulWidget> on State<T> {
  Timer? _cooldownTimer;
  int cooldown = 0;

  void disposeEmailCodeCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }

  void startEmailCodeCooldown(int seconds) {
    _cooldownTimer?.cancel();
    final sec = seconds.clamp(1, 600);
    setState(() => cooldown = sec);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (cooldown <= 1) {
        setState(() => cooldown = 0);
        timer.cancel();
      } else {
        setState(() => cooldown -= 1);
      }
    });
  }
}
