import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 联调 UI（API Base / user_id / 流式开关）是否可见。
/// Debug 包默认开；正式包可连点「我的」底部版本号 7 次解锁。
class DevFlags {
  DevFlags._();

  static const _kUnlocked = 'dev_ui_unlocked';
  static bool _unlocked = false;
  static bool _loaded = false;

  static bool get unlocked => _unlocked;

  static bool get showDevTools => kDebugMode || _unlocked;

  static Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _unlocked = sp.getBool(_kUnlocked) ?? false;
    _loaded = true;
  }

  static Future<void> setUnlocked(bool v) async {
    _unlocked = v;
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kUnlocked, v);
  }

  static Future<bool> toggleUnlocked() async {
    await setUnlocked(!_unlocked);
    return _unlocked;
  }
}
