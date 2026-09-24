import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'companion.dart';
import 'companion_native_video_controller.dart';
import 'companion_native_video_layer.dart';

/// 内置素材试玩：Android 走 Media3 PlatformView，其它平台走 video_player。
class CompanionVideoDemoPage extends StatefulWidget {
  const CompanionVideoDemoPage({super.key});

  static const mainClips = <String>[
    'assets/scenes/scene_a.mp4',
    'assets/scenes/scene_b.mp4',
  ];

  /// G02 母版 loop（换片后改回 loop_11 / loop_22）
  static const g02MainClips = <String>[
    'assets/scenes/loop_11.mp4',
    'assets/scenes/loop_22.mp4',
  ];

  static const insertClip = 'assets/scenes/loop_33.mp4';

  static const actionVideos = <String, String>{
    'insert': insertClip,
  };

  static bool get _useNativeAndroid => Platform.isAndroid;

  @override
  State<CompanionVideoDemoPage> createState() => _CompanionVideoDemoPageState();
}

class _CompanionVideoDemoPageState extends State<CompanionVideoDemoPage> {
  CompanionPlayVideoController? _flutterVideo;
  CompanionNativeVideoController? _nativeVideo;
  String? _error;
  bool _singleLoop = false;
  bool _starting = false;
  int _startGen = 0;

  bool get _ready => _flutterVideo != null || _nativeVideo != null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start(rotate: false));
  }

  @override
  void dispose() {
    _startGen++;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _flutterVideo?.dispose();
    _nativeVideo?.dispose();
    _flutterVideo = null;
    _nativeVideo = null;
    super.dispose();
  }

  Future<void> _start({required bool rotate}) async {
    if (_starting) return;
    _starting = true;
    final gen = ++_startGen;

    final oldFlutter = _flutterVideo;
    final oldNative = _nativeVideo;
    if (mounted) {
      setState(() {
        _error = null;
        _singleLoop = !rotate;
      });
    }

    final clips = rotate
        ? CompanionVideoDemoPage.g02MainClips
        : [CompanionVideoDemoPage.g02MainClips.first];

    try {
      if (CompanionVideoDemoPage._useNativeAndroid) {
        final existing = _nativeVideo;
        if (existing != null && existing.isAttached) {
          await existing.start(
            clips: clips,
            singleLoop: !rotate,
            actions: CompanionVideoDemoPage.actionVideos,
          );
          if (!mounted || gen != _startGen) return;
          oldFlutter?.dispose();
          return;
        }

        final ctrl = CompanionNativeVideoController();
        await ctrl.start(
          clips: clips,
          singleLoop: !rotate,
          actions: CompanionVideoDemoPage.actionVideos,
        );
        if (!mounted || gen != _startGen) {
          ctrl.dispose();
          return;
        }
        oldNative?.dispose();
        oldFlutter?.dispose();
        setState(() {
          _nativeVideo = ctrl;
          _flutterVideo = null;
        });
      } else {
        if (mounted) {
          setState(() {
            _flutterVideo = null;
            _nativeVideo = null;
          });
        }
        final ctrl = CompanionPlayVideoController(
          playlist: MainLoopPlaylist(clips),
          actionVideos: CompanionVideoDemoPage.actionVideos,
        );
        await ctrl.start();
        if (!mounted || gen != _startGen) {
          ctrl.dispose();
          return;
        }
        oldNative?.dispose();
        oldFlutter?.dispose();
        setState(() => _flutterVideo = ctrl);
      }
    } catch (e, st) {
      debugPrint('CompanionVideoDemo start failed: $e\n$st');
      if (mounted && gen == _startGen) {
        setState(() => _error = '$e');
      }
    } finally {
      if (gen == _startGen) _starting = false;
    }
  }

  void _queueInsert() {
    final native = _nativeVideo;
    if (native != null) {
      if (native.hasPendingAction) return;
      unawaited(native.queueAction('insert'));
      return;
    }
    final flutter = _flutterVideo;
    if (flutter != null && !flutter.hasPendingAction) {
      flutter.queueAction('insert');
    }
  }

  bool get _hasPendingAction =>
      _nativeVideo?.hasPendingAction == true || _flutterVideo?.hasPendingAction == true;

  String? get _pendingActionId =>
      _nativeVideo?.pendingActionId ?? _flutterVideo?.pendingActionId;

  bool get _showPlayerB =>
      _nativeVideo?.showPlayerB == true || _flutterVideo?.showPlayerB == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_nativeVideo != null)
            CompanionNativeVideoLayer(controller: _nativeVideo!)
          else if (_flutterVideo != null)
            CompanionPlayVideoLayer(
              controller: _flutterVideo!,
              coverAsset: 'assets/scenes/anchor.jpg',
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white54)),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
                const Spacer(),
                if (_ready) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${CompanionVideoDemoPage._useNativeAndroid ? 'Media3' : 'Flutter'} · '
                      'Player ${_showPlayerB ? 'B' : 'A'} · '
                      '${_singleLoop ? '主循环 · loop_11' : '双路 · loop_11↔22 预载切换'}'
                      '${_hasPendingAction ? ' · 插入排队: loop_33' : ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _starting ? null : () => _start(rotate: false),
                            child: const Text('主循环'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                            ),
                            onPressed: _starting ? null : () => _start(rotate: true),
                            child: const Text('双路切换'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: '片尾插入 loop_33',
                          onPressed: _hasPendingAction ? null : _queueInsert,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton.filled(
                          tooltip: '排队盖毯（待出片）',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '盖毯动作片尚未出片。请用可灵按母版生成后放到 assets/scenes/action_blanket.mp4',
                                ),
                                duration: Duration(seconds: 4),
                              ),
                            );
                          },
                          icon: const Icon(Icons.dry_cleaning_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
