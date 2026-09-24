import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../personas/persona_cover.dart';
import 'companion_play_video_controller.dart';
import 'companion_video_frame.dart';

/// 陪伴场景全屏视频层：屏幕上只挂一个纹理槽，切换 11/22 时只换 controller。
class CompanionPlayVideoLayer extends StatefulWidget {
  const CompanionPlayVideoLayer({
    super.key,
    required this.controller,
    this.coverUrl,
    this.coverAsset,
    this.baseUrl = '',
    this.coverFallbackColor = Colors.black,
  });

  final CompanionPlayVideoController controller;
  final String? coverUrl;
  final String? coverAsset;
  final String baseUrl;
  final Color coverFallbackColor;

  @override
  State<CompanionPlayVideoLayer> createState() => _CompanionPlayVideoLayerState();
}

class _CompanionPlayVideoLayerState extends State<CompanionPlayVideoLayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant CompanionPlayVideoLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.isVideoReady;
    final active = c.activeController;

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = companionCoverRect(constraints.biggest);

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (active != null && _isUsable(active))
                CompanionSingleVideoView(
                  key: const ValueKey('companion_single_slot'),
                  controller: active,
                  viewport: viewport,
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ready ? 0 : 1,
                    child: _Cover(
                      baseUrl: widget.baseUrl,
                      coverUrl: widget.coverUrl,
                      coverAsset: widget.coverAsset,
                      fallbackColor: widget.coverFallbackColor,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.baseUrl,
    required this.coverUrl,
    required this.coverAsset,
    required this.fallbackColor,
  });

  final String baseUrl;
  final String? coverUrl;
  final String? coverAsset;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final asset = coverAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(asset, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    final url = coverUrl;
    final resolved = resolvePersonaCoverUrl(baseUrl, url);
    if (resolved != null && resolved.isNotEmpty) {
      return AppNetworkImage(
        url: resolved,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return ColoredBox(color: fallbackColor);
  }
}

bool _isUsable(VideoPlayerController controller) {
  try {
    return controller.value.isInitialized && !controller.value.hasError;
  } catch (_) {
    return false;
  }
}
