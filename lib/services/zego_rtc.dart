import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

typedef ZegoRtcStatusCallback = void Function(String message);

/// ZEGO Express RTC：进房、推用户音频流、事件驱动拉 Agent 流。
class ZegoRtcSession {
  ZegoRtcSession({
    required this.appId,
    required this.roomId,
    required this.userId,
    required this.userToken,
    required this.userStreamId,
    this.agentStreamId,
    this.agentUserId,
    this.onStatus,
  });

  final int appId;
  final String roomId;
  final String userId;
  final String userToken;
  final String userStreamId;
  final String? agentStreamId;
  final String? agentUserId;
  final ZegoRtcStatusCallback? onStatus;

  static ZegoRtcSession? _active;

  bool _joined = false;
  final Set<String> _playingStreamIds = {};
  Timer? _playRetryTimer;

  void _scheduleAgentPlayRetries() {
    _playRetryTimer?.cancel();
    var attempts = 0;
    _playRetryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_joined || attempts >= 20) {
        timer.cancel();
        return;
      }
      attempts += 1;
      _tryPlayAgentStream('重试#$attempts');
      unawaited(_syncRoomStreams(ZegoExpressEngine.instance));
    });
  }

  void _hint(String message) {
    debugPrint('[ZegoRtc] $message');
    onStatus?.call(message);
  }

  Future<void> join() async {
    if (appId <= 0) {
      throw StateError('无效的 ZEGO AppID');
    }
    if (!kIsWeb) {
      _hint('申请麦克风权限…');
      final mic = await Permission.microphone
          .request()
          .timeout(const Duration(seconds: 45), onTimeout: () {
        return PermissionStatus.denied;
      });
      if (!mic.isGranted) {
        throw StateError('需要麦克风权限才能语音通话，请在系统设置中允许');
      }
    }

    _installHandlers();
    _hint('初始化 RTC 引擎…');
    try {
      await ZegoExpressEngine.destroyEngine();
    } catch (_) {}
    await ZegoExpressEngine.createEngineWithProfile(
      ZegoEngineProfile(
        appId,
        ZegoScenario.StandardVoiceCall,
        appSign: null,
      ),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError('RTC 引擎初始化超时'),
    );

    final engine = ZegoExpressEngine.instance;
    await engine.enableCamera(false);
    await engine.mutePublishStreamVideo(true);
    await engine.muteSpeaker(false);
    await engine.muteAllPlayStreamAudio(false);
    await engine.setAudioRouteToSpeaker(true);

    final config = ZegoRoomConfig.defaultConfig()
      ..isUserStatusNotify = true
      ..token = userToken;

    _hint('正在进入房间…');
    final result = await engine
        .loginRoom(
          roomId,
          ZegoUser(userId, userId),
          config: config,
        )
        .timeout(
          const Duration(seconds: 45),
          onTimeout: () => ZegoRoomLoginResult(-1, {}),
        );
    if (result.errorCode != 0) {
      await leave();
      throw StateError(
        result.errorCode == -1
            ? 'RTC 进房超时，请检查网络或稍后重试'
            : 'RTC 进房失败 (${result.errorCode})',
      );
    }

    _hint('正在发布麦克风…');
    try {
      await engine.startPublishingStream(userStreamId).timeout(
        const Duration(seconds: 20),
      );
    } on TimeoutException {
      debugPrint('[ZegoRtc] publish timeout $userStreamId (继续拉 AI 音频)');
    } catch (e) {
      debugPrint('[ZegoRtc] publish failed: $e');
    }

    _tryPlayAgentStream('进房后');
    await _syncRoomStreams(engine);
    _scheduleAgentPlayRetries();
    _joined = true;
    _hint('音频通道已就绪');
  }

  void _installHandlers() {
    _active = this;
    ZegoExpressEngine.onRoomStreamUpdate = (
      String roomID,
      ZegoUpdateType updateType,
      List<ZegoStream> streamList,
      Map<String, dynamic> extendedData,
    ) {
      _active?._onRoomStreamUpdate(roomID, updateType, streamList);
    };
    ZegoExpressEngine.onRoomStateChanged = (
      String roomID,
      ZegoRoomStateChangedReason reason,
      int errorCode,
      Map<String, dynamic> extendedData,
    ) {
      if (_active == null || roomID != _active!.roomId) return;
      debugPrint('[ZegoRtc] roomState reason=$reason code=$errorCode');
    };
    ZegoExpressEngine.onPlayerStateUpdate = (
      String streamID,
      ZegoPlayerState state,
      int errorCode,
      Map<String, dynamic> extendedData,
    ) {
      _active?._onPlayerStateUpdate(streamID, state, errorCode);
    };
  }

  void _onPlayerStateUpdate(
    String streamID,
    ZegoPlayerState state,
    int errorCode,
  ) {
    debugPrint('[ZegoRtc] player $streamID state=$state code=$errorCode');
    if (state == ZegoPlayerState.Playing) {
      _hint('AI 正在说话…');
    } else if (state == ZegoPlayerState.PlayRequesting) {
      _hint('正在拉取 AI 音频…');
    } else if (state == ZegoPlayerState.NoPlay && errorCode != 0) {
      _playingStreamIds.remove(streamID);
      _hint('AI 音频拉取失败 ($errorCode)');
    }
  }

  void _clearHandlers() {
    if (_active == this) {
      ZegoExpressEngine.onRoomStreamUpdate = null;
      ZegoExpressEngine.onRoomStateChanged = null;
      ZegoExpressEngine.onPlayerStateUpdate = null;
      _active = null;
    }
  }

  void _onRoomStreamUpdate(
    String roomID,
    ZegoUpdateType updateType,
    List<ZegoStream> streamList,
  ) {
    if (roomID != roomId || updateType != ZegoUpdateType.Add) return;
    for (final stream in streamList) {
      if (_shouldPlayStream(stream.streamID)) {
        _playStream(stream.streamID, '检测到 Agent 推流');
      }
    }
  }

  bool _shouldPlayStream(String streamId) {
    if (streamId.isEmpty || streamId == userStreamId) return false;
    final target = agentStreamId;
    if (target != null && target.isNotEmpty && streamId == target) {
      return true;
    }
    final agentUser = agentUserId;
    if (agentUser != null &&
        agentUser.isNotEmpty &&
        (streamId == agentUser || streamId.contains(agentUser))) {
      return true;
    }
    // ZEGO Agent 实际推流 ID 可能与注册时不完全一致，兜底拉任意远端音频流。
    if (streamId.startsWith('a_stream_')) return true;
    if (streamId.contains('agent')) return true;
    return false;
  }

  Future<void> _syncRoomStreams(ZegoExpressEngine engine) async {
    try {
      final list = await engine
          .getRoomStreamList(roomId, ZegoRoomStreamListType.Play)
          .timeout(const Duration(seconds: 5));
      for (final stream in list.playStreamList) {
        if (_shouldPlayStream(stream.streamID)) {
          await _playStream(stream.streamID, 'roomStreamList');
        }
      }
    } catch (e) {
      debugPrint('[ZegoRtc] getRoomStreamList failed: $e');
    }
  }

  void _tryPlayAgentStream(String reason) {
    final target = agentStreamId;
    if (target == null || target.isEmpty) return;
    unawaited(_playStream(target, reason));
  }

  Future<void> _playStream(String streamId, String reason) async {
    if (_playingStreamIds.contains(streamId)) return;
    _playingStreamIds.add(streamId);
    _hint('正在拉取 AI 音频…');
    try {
      await ZegoExpressEngine.instance.startPlayingStream(streamId).timeout(
        const Duration(seconds: 20),
      );
      await ZegoExpressEngine.instance.setPlayVolume(streamId, 100);
      await ZegoExpressEngine.instance.mutePlayStreamAudio(streamId, false);
      await ZegoExpressEngine.instance.setAudioRouteToSpeaker(true);
      _hint('AI 音频已连接');
      debugPrint('[ZegoRtc] playing $streamId ($reason)');
    } on TimeoutException {
      _playingStreamIds.remove(streamId);
      debugPrint('[ZegoRtc] play timeout $streamId ($reason)');
    } catch (e) {
      _playingStreamIds.remove(streamId);
      debugPrint('[ZegoRtc] play failed $streamId: $e');
    }
  }

  Future<void> leave() async {
    _playRetryTimer?.cancel();
    _playRetryTimer = null;
    _clearHandlers();
    if (!_joined) {
      try {
        await ZegoExpressEngine.destroyEngine();
      } catch (_) {}
      return;
    }
    try {
      await ZegoExpressEngine.instance.stopPublishingStream();
      for (final streamId in _playingStreamIds.toList()) {
        try {
          await ZegoExpressEngine.instance.stopPlayingStream(streamId);
        } catch (_) {}
      }
      _playingStreamIds.clear();
      await ZegoExpressEngine.instance.logoutRoom(roomId);
    } catch (_) {
      // 挂断时尽力清理即可
    } finally {
      _joined = false;
      try {
        await ZegoExpressEngine.destroyEngine();
      } catch (_) {}
    }
  }
}
