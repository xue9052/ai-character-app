import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 每 [windowSize] 轮窗口内，在 [minTurn]～[maxTurn] 随机选 1 次语音回复。
class VoiceReplyPlanner {
  VoiceReplyPlanner({
    this.minTurn = 4,
    this.maxTurn = 10,
    this.windowSize = 10,
    int windowIdx = -1,
    int targetTurn = 0,
    bool used = false,
    int userTurnCount = 0,
  })  : _windowIdx = windowIdx,
        _targetTurn = targetTurn,
        _used = used,
        _userTurnCount = userTurnCount;

  final int minTurn;
  final int maxTurn;
  final int windowSize;

  int _windowIdx;
  int _targetTurn;
  bool _used;
  int _userTurnCount;

  int get userTurnCount => _userTurnCount;

  static String _key(String userId, String scopeId) =>
      'voice_reply_${userId.trim()}_${scopeId.trim()}';

  static Future<VoiceReplyPlanner> load({
    required String userId,
    required String scopeId,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(userId, scopeId));
    if (raw == null || raw.isEmpty) {
      return VoiceReplyPlanner();
    }
    final parts = raw.split(':');
    if (parts.length < 5) return VoiceReplyPlanner();
    return VoiceReplyPlanner(
      windowIdx: int.tryParse(parts[0]) ?? -1,
      targetTurn: int.tryParse(parts[1]) ?? 0,
      used: parts[2] == '1',
      userTurnCount: int.tryParse(parts[3]) ?? 0,
      minTurn: int.tryParse(parts[4]) ?? 4,
      maxTurn: int.tryParse(parts.length > 5 ? parts[5] : '10') ?? 10,
      windowSize: int.tryParse(parts.length > 6 ? parts[6] : '10') ?? 10,
    );
  }

  Future<void> save({
    required String userId,
    required String scopeId,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key(userId, scopeId),
      '$_windowIdx:$_targetTurn:${_used ? 1 : 0}:$_userTurnCount:$minTurn:$maxTurn:$windowSize',
    );
  }

  int _turnInWindow(int turn) => ((turn - 1) % windowSize) + 1;

  /// 用户即将发送第 [turn] 条消息时，判断是否为本窗口的语音轮次。
  bool shouldVoiceForTurn(int turn) {
    final t = turn.clamp(1, 999999);
    final windowIdx = (t - 1) ~/ windowSize;
    final turnInWindow = _turnInWindow(t);
    if (turnInWindow < minTurn || turnInWindow > maxTurn) {
      return false;
    }
    if (_windowIdx != windowIdx) {
      _windowIdx = windowIdx;
      _targetTurn = minTurn + Random().nextInt(maxTurn - minTurn + 1);
      _used = false;
    }
    if (_used) return false;
    if (turnInWindow == _targetTurn) {
      _used = true;
      return true;
    }
    return false;
  }

  void syncTurnCount(int count) {
    _userTurnCount = count < 0 ? 0 : count;
    final windowIdx = _userTurnCount <= 0 ? -1 : (_userTurnCount - 1) ~/ windowSize;
    if (windowIdx != _windowIdx) {
      _windowIdx = windowIdx;
      _targetTurn = 0;
      _used = false;
    }
  }

  /// 记录一次用户发言并返回是否应附带语音。
  bool markUserSent() {
    _userTurnCount += 1;
    return shouldVoiceForTurn(_userTurnCount);
  }
}
