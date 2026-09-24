import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Media3 双机位编排（与 [CompanionPlayVideoController] 试玩 API 对齐）。
class CompanionNativeVideoController extends ChangeNotifier {
  CompanionNativeVideoController();

  static const _viewType = 'companion_video_view';

  MethodChannel? _channel;
  Map<String, dynamic>? _pendingStart;
  int? _attachedViewId;
  String? _error;

  bool isVideoReady = false;
  bool showPlayerB = false;
  String? pendingActionId;

  bool get hasPendingAction => pendingActionId != null;
  bool get activeIsB => showPlayerB;
  bool get isAttached => _channel != null;
  String? get error => _error;

  static const String platformViewType = _viewType;

  void attach(int viewId) {
    if (_attachedViewId == viewId && _channel != null) return;
    _attachedViewId = viewId;
    _channel = MethodChannel('com.aichar.ai_character_app/companion_video_$viewId');
    _channel!.setMethodCallHandler(_onNativeCall);
    final pending = _pendingStart;
    if (pending != null) {
      unawaited(_invokeStart(pending));
    }
  }

  Future<void> start({
    required List<String> clips,
    required bool singleLoop,
    Map<String, String> actions = const {},
  }) async {
    _error = null;
    final args = <String, dynamic>{
      'clips': clips,
      'singleLoop': singleLoop,
      'actions': actions,
    };
    if (_channel == null) {
      _pendingStart = args;
      isVideoReady = false;
      notifyListeners();
      return;
    }
    await _invokeStart(args);
  }

  Future<void> _invokeStart(Map<String, dynamic> args) async {
    _pendingStart = null;
    isVideoReady = false;
    notifyListeners();
    try {
      await _channel!.invokeMethod<void>('start', args);
    } on PlatformException catch (e) {
      _error = e.message ?? e.code;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> queueAction(String actionId) async {
    await _channel?.invokeMethod<void>('queueAction', {'actionId': actionId});
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        isVideoReady = true;
        notifyListeners();
      case 'state':
        final map = call.arguments as Map<dynamic, dynamic>?;
        if (map != null) {
          final newB = map['activeIsB'] == true;
          final newPending = map['pendingActionId'] as String?;
          if (newB == showPlayerB && newPending == pendingActionId) return;
          showPlayerB = newB;
          pendingActionId = newPending;
          notifyListeners();
        }
      case 'error':
        final map = call.arguments as Map<dynamic, dynamic>?;
        _error = map?['message'] as String? ?? 'native playback error';
        debugPrint('CompanionNativeVideo error: $_error');
        notifyListeners();
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_channel?.invokeMethod<void>('dispose'));
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _attachedViewId = null;
    super.dispose();
  }
}
