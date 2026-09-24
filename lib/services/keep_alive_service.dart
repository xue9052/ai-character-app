import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 常驻前台服务：把进程钉住，让群聊 WebSocket 在后台不断开。
///
/// 任务被划掉后 Flutter 引擎会销毁，长连接无法维持，届时由 JPush 离线推送兜底。
class KeepAliveService {
  KeepAliveService._();

  static final KeepAliveService instance = KeepAliveService._();

  static const _channel =
      MethodChannel('com.aichar.ai_character_app/keepalive');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  bool _running = false;

  bool get running => _running;

  Future<bool> start({String? text}) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('start', {'text': text});
      _running = ok ?? false;
    } on PlatformException {
      _running = false;
    } on MissingPluginException {
      _running = false;
    }
    return _running;
  }

  Future<void> stop() async {
    if (!supported) return;
    _running = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // 忽略：服务本就没起来
    } on MissingPluginException {
      // 忽略：旧包没有原生实现
    }
  }

  Future<bool> isRunning() async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isRunning');
      _running = ok ?? false;
    } catch (_) {
      _running = false;
    }
    return _running;
  }

  /// 是否已加入电池优化白名单（国产 ROM 不加白名单后台仍可能被冻结）。
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!supported) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 拉起系统「忽略电池优化」授权弹窗，失败时退回省电设置页。
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!supported) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
