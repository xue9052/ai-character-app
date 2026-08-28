import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../services/zego_rtc.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';

/// 语音通话页：对接 /v1/calls/start|hangup + ZEGO Express RTC。
class VoiceCallPage extends StatefulWidget {
  static const buildTag = 'vcall-250826e';

  const VoiceCallPage({
    super.key,
    required this.personaId,
    required this.personaName,
    required this.accessToken,
    required this.baseUrl,
    this.sessionId,
  });

  final String personaId;
  final String personaName;
  final String accessToken;
  final String baseUrl;
  final String? sessionId;

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  bool _loading = true;
  bool _inCall = false;
  bool _hangingUp = false;
  String? _error;
  String? _callId;
  Map<String, dynamic>? _startPayload;
  ZegoRtcSession? _rtc;
  bool _rtcReady = false;
  String _statusHint = '正在连接…';
  String _debugLine = '';
  Timer? _timer;
  Timer? _watchdog;
  int _elapsedSec = 0;
  int _freeRemainingSec = 0;
  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(widget.baseUrl, accessToken: widget.accessToken);
    _debugLine = '${VoiceCallPage.buildTag} · ${widget.baseUrl}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watchdog?.cancel();
    if (_inCall && _callId != null && !_hangingUp) {
      _hangup(silent: true);
    } else {
      _rtc?.leave();
    }
    super.dispose();
  }

  int _parseAppId(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse('$raw') ?? 0;
  }

  Future<void> _joinRtc(Map<String, dynamic> data) async {
    final appId = _parseAppId(data['app_id']);
    final roomId = '${data['room_id'] ?? ''}';
    final userId = '${data['user_id'] ?? ''}';
    final token = '${data['user_token'] ?? ''}';
    final userStreamId = '${data['user_stream_id'] ?? ''}';
    final agentStreamId = data['agent_stream_id'] as String?;
    final agentUserId = data['agent_user_id'] as String?;

    if (roomId.isEmpty || userId.isEmpty || token.isEmpty || userStreamId.isEmpty) {
      throw StateError('通话参数不完整，请重试');
    }

    final session = ZegoRtcSession(
      appId: appId,
      roomId: roomId,
      userId: userId,
      userToken: token,
      userStreamId: userStreamId,
      agentStreamId: agentStreamId,
      agentUserId: agentUserId,
      onStatus: (msg) {
        if (mounted) setState(() => _statusHint = msg);
      },
    );
    await session.join().timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw StateError('连接音频通道超时，请挂断后重试'),
    );
    if (!mounted) {
      await session.leave();
      return;
    }
    setState(() {
      _rtc = session;
      _rtcReady = true;
    });
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 35), () {
      if (!mounted || !_loading) return;
      setState(() {
        _error =
            '连接超时（$_statusHint）。请确认已安装最新 APK，且服务器为 ${widget.baseUrl}';
        _loading = false;
      });
    });
  }

  Future<void> _bootstrap() async {
    final token = widget.accessToken.trim();
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    _armWatchdog();
    await _startCall(token);
  }

  Future<void> _startCall(String token) async {
    setState(() {
      _loading = true;
      _error = null;
      _statusHint = '正在创建通话…';
    });
    try {
      final data = await _api.startVoiceCall(
            accessToken: token,
            personaId: widget.personaId,
            sessionId: widget.sessionId,
          );
      _watchdog?.cancel();
      final quota = data['quota'];
      if (quota is Map) {
        final free = quota['free_seconds_remaining'];
        _freeRemainingSec = free is int ? free : int.tryParse('$free') ?? 0;
      }
      setState(() {
        _loading = false;
        _inCall = true;
        _startPayload = data;
        _callId = data['call_id'] as String?;
        _rtcReady = false;
        _statusHint = '正在申请麦克风并进房…';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSec++);
      });
      try {
        await _joinRtc(data);
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = e is StateError ? e.message : apiErrorMessage(e);
            _inCall = false;
            _rtcReady = false;
            _statusHint = '';
          });
        }
        final callId = _callId;
        if (callId != null) {
          try {
            await _api.hangupVoiceCall(accessToken: token, callId: callId);
          } catch (_) {}
        }
      }
    } on TimeoutException {
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = '创建通话超时，ZEGO 可能繁忙，请稍后重试';
        _statusHint = '';
      });
    } catch (e) {
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
        _statusHint = '';
      });
    }
  }

  Future<void> _hangup({bool silent = false}) async {
    final callId = _callId;
    if (callId == null || _hangingUp) return;
    _hangingUp = true;
    _timer?.cancel();
    await _rtc?.leave();
    _rtc = null;
    _rtcReady = false;
    final token = widget.accessToken.trim();
    try {
      if (token.isNotEmpty) {
        await _api.hangupVoiceCall(accessToken: token, callId: callId);
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('挂断请求失败，请重试')),
        );
      }
    } finally {
      _hangingUp = false;
      if (mounted) {
        setState(() => _inCall = false);
        if (!silent) Navigator.of(context).pop();
      }
    }
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.personaName;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('与 $name 语音通话'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(fontSize: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.white54),
                      const SizedBox(height: 12),
                      Text(
                        _statusHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      if (_debugLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _debugLine,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                )
              else if (_inCall) ...[
                Text(
                  _formatDuration(_elapsedSec),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '剩余免费 ${_freeRemainingSec ~/ 60} 分 ${_freeRemainingSec % 60} 秒',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 12),
                Text(
                  _rtcReady
                      ? (_statusHint.isNotEmpty ? _statusHint : '通话中 · 请直接说话')
                      : (_statusHint.isNotEmpty ? _statusHint : '正在连接音频通道…'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
              const Spacer(),
              if (_inCall)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _hangingUp ? null : () => _hangup(),
                    icon: _hangingUp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_end),
                    label: Text(_hangingUp ? '挂断中…' : '挂断'),
                  ),
                )
              else if (_error != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
