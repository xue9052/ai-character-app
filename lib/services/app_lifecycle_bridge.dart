import 'dart:io';

import 'package:flutter/services.dart';

/// Android：根页面返回时退到桌面而不是 finish Activity，便于热恢复。
class AppLifecycleBridge {
  AppLifecycleBridge._();

  static const _channel = MethodChannel('com.aichar.ai_character_app/lifecycle');

  static Future<void> moveToBackground() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('moveTaskToBack');
    } on PlatformException {
      // 忽略：旧包或未实现时仍走系统默认
    }
  }
}
