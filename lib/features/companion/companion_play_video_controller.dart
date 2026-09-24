import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import 'main_loop_playlist.dart';
import 'companion_video_frame.dart';

/// 双机位视频编排：active 前台播，standby 后台预载；片尾 [tryCompleteTransition] 换层。
///
/// Android 上通常只能一路硬解同时播放，因此 standby 只 initialize + pause，
/// 不在 active 播放期间对 standby 调用 play()。
class CompanionPlayVideoController extends ChangeNotifier {
  CompanionPlayVideoController({
    required this.playlist,
    this.actionVideos = const {},
  });

  static const Duration actionPreloadTimeout = Duration(seconds: 8);
  static const Duration mainPreloadTimeout = Duration(seconds: 10);

  final MainLoopPlaylist playlist;
  final Map<String, String> actionVideos;

  VideoPlayerController? _controllerA;
  VideoPlayerController? _controllerB;
  String? _urlA;
  String? _urlB;

  /// 与 [showPlayerB] 同步：true 表示 B 为 active。
  bool activeIsB = false;
  bool showPlayerB = false;

  bool isVideoReady = false;
  bool _disposed = false;

  String? _standbyUrl;
  bool _standbyPrimed = false;

  String? _pendingActionId;
  String? _pendingActionUrl;
  bool _playingAction = false;

  Timer? _actionTimeout;

  bool _endHandled = false;

  VideoPlayerController? get controllerA => _controllerA;
  VideoPlayerController? get controllerB => _controllerB;

  /// 当前前台播放的 controller（UI 只挂这一路纹理）。
  VideoPlayerController? get activeController => _activeOrNull;

  VideoPlayerController? get _activeOrNull =>
      activeIsB ? _controllerB : _controllerA;

  VideoPlayerController? get _standbyOrNull =>
      activeIsB ? _controllerA : _controllerB;

  VideoPlayerController get _active => _activeOrNull!;

  VideoPlayerController get _standby => _standbyOrNull!;

  bool get hasPendingAction => _pendingActionUrl != null;

  String? get pendingActionId => _pendingActionId;

  Future<void> start() async {
    final first = playlist.current;
    _controllerA = await _createController(first);
    _urlA = first;
    if (_disposed) return;

    if (!playlist.isSingle) {
      final second = playlist.next!;
      _controllerB = await _createController(second);
      _urlB = second;
      _standbyUrl = second;
      await _primeDecoder(_controllerB!);
      _standbyPrimed = _controllerB!.value.isInitialized;
    }
    if (_disposed) return;

    activeIsB = false;
    showPlayerB = false;

    _controllerA!.setVolume(1.0);
    if (playlist.isSingle) {
      await _controllerA!.setLooping(true);
      await _controllerA!.play();
    } else {
      _controllerB!.setVolume(0.0);
      await _controllerB!.pause();
      await _controllerA!.play();
    }

    isVideoReady = true;
    notifyListeners();
  }

  Future<VideoPlayerController> _createController(String url) async {
    final VideoPlayerController c = url.startsWith('assets/')
        ? VideoPlayerController.asset(
            url,
            videoPlayerOptions: kCompanionVideoPlayerOptions,
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            videoPlayerOptions: kCompanionVideoPlayerOptions,
          );
    _attachEndedListener(c);
    await c.initialize();
    await c.pause();
    return c;
  }

  void _attachEndedListener(VideoPlayerController c) {
    c.addListener(() {
      if (_disposed || !c.value.isInitialized) return;
      final active = _activeOrNull;
      if (active == null || c != active) return;
      if (!active.value.isPlaying) return;
      if (_shouldUseNativeLoop(active)) return;
      final dur = c.value.duration;
      if (dur == Duration.zero) return;
      if (c.value.position >= dur - const Duration(milliseconds: 60)) {
        _onActiveNearEnd();
      }
    });
  }

  bool _shouldUseNativeLoop(VideoPlayerController c) {
    return playlist.isSingle &&
        !_playingAction &&
        _pendingActionUrl == null &&
        c.value.isLooping;
  }

  void _onActiveNearEnd() {
    if (_endHandled) return;
    _endHandled = true;
    unawaited(_tryCompleteTransition().whenComplete(() {
      _endHandled = false;
    }));
  }

  void queueAction(String actionId) {
    final url = actionVideos[actionId];
    if (url == null || url.isEmpty) return;
    if (_pendingActionUrl != null) return;

    _pendingActionId = actionId;
    _pendingActionUrl = url;
    _actionTimeout?.cancel();
    _actionTimeout = Timer(actionPreloadTimeout, () {
      if (_pendingActionUrl == url) {
        _pendingActionId = null;
        _pendingActionUrl = null;
        _restoreNativeLoopIfIdle();
        notifyListeners();
      }
    });
    if (playlist.isSingle) {
      unawaited(_active.setLooping(false));
    }
    unawaited(_preloadStandby(url));
    notifyListeners();
  }

  void cancelPendingAction() {
    _actionTimeout?.cancel();
    _pendingActionId = null;
    _pendingActionUrl = null;
    _restoreNativeLoopIfIdle();
    notifyListeners();
  }

  void _restoreNativeLoopIfIdle() {
    if (!playlist.isSingle || _playingAction) return;
    unawaited(_active.setLooping(true));
  }

  Future<void> _tryCompleteTransition() async {
    if (_disposed) return;

    if (_pendingActionUrl != null) {
      final url = _pendingActionUrl!;
      final ready = await _ensureStandbyReady(url, mainPreloadTimeout);
      if (!ready) {
        cancelPendingAction();
        await _replayActive();
        return;
      }
      _pendingActionId = null;
      _pendingActionUrl = null;
      _actionTimeout?.cancel();
      _playingAction = true;
      await swapToStandby();
      return;
    }

    if (_playingAction) {
      _playingAction = false;
    }

    if (playlist.isSingle) {
      await _returnToMainLoop();
      return;
    }

    final nextUrl = playlist.next!;
    final ready = await _ensureStandbyReady(nextUrl, mainPreloadTimeout);
    if (!ready) {
      await _replayActive();
      return;
    }
    playlist.advance();
    await swapToStandby();
  }

  Future<void> swapToStandby() async {
    if (_disposed) return;

    final oldActive = _active;
    final newActive = _standby;

    newActive.setVolume(1.0);
    if (newActive.value.position > Duration.zero || _isEnded(newActive)) {
      await newActive.seekTo(Duration.zero);
    }

    // 与 HTML 一致：先起播 standby，再切显隐，最后停旧层（重叠几帧减少空档）。
    await newActive.play();

    activeIsB = !activeIsB;
    showPlayerB = activeIsB;
    notifyListeners();

    oldActive.setVolume(0.0);
    if (_isEnded(oldActive)) {
      await oldActive.seekTo(Duration.zero);
    } else {
      await oldActive.pause();
    }

    _standbyPrimed = false;

    if (!_playingAction && !playlist.isSingle) {
      unawaited(_preloadStandby(playlist.next!));
    } else if (!_playingAction && playlist.isSingle) {
      _clearStandbyPrime();
    }
  }

  bool _isEnded(VideoPlayerController c) {
    if (!c.value.isInitialized) return false;
    final dur = c.value.duration;
    if (dur == Duration.zero) return false;
    return c.value.position >= dur - const Duration(milliseconds: 80);
  }

  Future<void> _returnToMainLoop() async {
    final mainUrl = playlist.current;
    if (_controllerUrl(_active) == mainUrl) {
      final c = _active;
      c.setVolume(1.0);
      await c.setLooping(true);
      if (_isEnded(c)) {
        await c.seekTo(Duration.zero);
      }
      if (!c.value.isPlaying) {
        await c.play();
      }
      notifyListeners();
      return;
    }

    if (_controllerUrl(_standby) != mainUrl) {
      final ready = await _ensureStandbyReady(mainUrl, mainPreloadTimeout);
      if (!ready) {
        await _replayActive();
        return;
      }
    }

    final standby = _standby;
    standby.setVolume(1.0);
    await standby.setLooping(true);
    await standby.seekTo(Duration.zero);
    await swapToStandby();
  }

  Future<void> _replayActive() async {
    final c = _active;
    c.setVolume(1.0);
    if (_isEnded(c)) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
    notifyListeners();
  }

  Future<bool> _ensureStandbyReady(String url, Duration timeout) async {
    if (_standbyUrl == url && _standbyPrimed) return true;

    try {
      await _preloadStandby(url).timeout(timeout);
    } catch (e) {
      debugPrint('CompanionPlayVideo ensureStandby failed: $e');
      return false;
    }
    return _standbyUrl == url && _standbyPrimed;
  }

  String? _controllerUrl(VideoPlayerController c) {
    if (c == _controllerA) return _urlA;
    if (c == _controllerB) return _urlB;
    return null;
  }

  Future<void> _replaceStandbyController(String url) async {
    final wasB = activeIsB;
    final old = _standby;
    await old.pause();

    final fresh = await _createController(url);
    if (_disposed) {
      await fresh.dispose();
      return;
    }
    if (wasB) {
      _controllerA = fresh;
      _urlA = url;
    } else {
      _controllerB = fresh;
      _urlB = url;
    }
    notifyListeners();

    // 等 UI 切到新 controller 后再 dispose，避免 VideoPlayer 红屏闪一下。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(old.dispose());
    });
  }

  Future<void> _ensureStandbyController(String url) async {
    if (_standbyOrNull != null) return;

    final fresh = await _createController(url);
    if (_disposed) {
      await fresh.dispose();
      return;
    }
    if (activeIsB) {
      _controllerA = fresh;
      _urlA = url;
    } else {
      _controllerB = fresh;
      _urlB = url;
    }
    notifyListeners();
  }

  Future<void> _primeDecoder(VideoPlayerController c) async {
    c.setVolume(0.0);
    await c.seekTo(Duration.zero);
    await c.play();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.pause();
  }

  /// 仅换源 + initialize，standby 保持 pause，不与 active 同时 play。
  Future<void> _preloadStandby(String url) async {
    if (_disposed) return;
    if (playlist.isSingle && url == playlist.current) return;

    _standbyUrl = url;
    _standbyPrimed = false;
    notifyListeners();

    try {
      await _ensureStandbyController(url);

      final currentUrl = _controllerUrl(_standby);
      if (currentUrl != url) {
        await _replaceStandbyController(url);
      }

      final s = _standby;
      s.setVolume(0.0);
      await s.seekTo(Duration.zero);
      await s.pause();
      _standbyPrimed = s.value.isInitialized;
      notifyListeners();
    } catch (e) {
      debugPrint('CompanionPlayVideo preload failed: $e');
      _standbyPrimed = false;
      notifyListeners();
      rethrow;
    }
  }

  void _clearStandbyPrime() {
    _standbyUrl = null;
    _standbyPrimed = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _actionTimeout?.cancel();
    _controllerA?.dispose();
    _controllerB?.dispose();
    _controllerA = null;
    _controllerB = null;
    super.dispose();
  }
}
