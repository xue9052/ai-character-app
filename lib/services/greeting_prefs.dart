import 'package:shared_preferences/shared_preferences.dart';

/// 用户对本角色跳过开场白；清空聊天后清除，可再次出现。
class GreetingPrefs {
  GreetingPrefs._();

  static String _key(String userId, String personaId) =>
      'greeting_skipped_${userId}_$personaId';

  static Future<bool> isSkipped({
    required String userId,
    required String personaId,
  }) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_key(userId, personaId)) ?? false;
  }

  static Future<void> setSkipped({
    required String userId,
    required String personaId,
    required bool skipped,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (skipped) {
      await sp.setBool(_key(userId, personaId), true);
    } else {
      await sp.remove(_key(userId, personaId));
    }
  }
}
