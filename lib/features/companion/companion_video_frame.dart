import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 陪伴场景素材统一画幅（mubanh 11/22 等为 720×1280 竖屏）。
const Size kCompanionVideoFrame = Size(720, 1280);

const double kCompanionVideoAspect = 720 / 1280;

VideoPlayerOptions get kCompanionVideoPlayerOptions => VideoPlayerOptions(mixWithOthers: true);

/// 计算全屏 [BoxFit.cover] 视口。
Rect companionCoverRect(Size screen) {
  final sw = screen.width;
  final sh = screen.height;
  if (sw <= 0 || sh <= 0) return Rect.zero;

  final screenAspect = sw / sh;
  late double w;
  late double h;
  if (screenAspect > kCompanionVideoAspect) {
    w = sw;
    h = sw / kCompanionVideoAspect;
  } else {
    h = sh;
    w = sh * kCompanionVideoAspect;
  }
  return Rect.fromCenter(
    center: Offset(sw / 2, sh / 2),
    width: w,
    height: h,
  );
}

/// 单槽视频：全屏只挂一个 [VideoPlayer]，切换片源时只换 [controller]。
class CompanionSingleVideoView extends StatefulWidget {
  const CompanionSingleVideoView({
    super.key,
    required this.controller,
    required this.viewport,
  });

  final VideoPlayerController controller;
  final Rect viewport;

  @override
  State<CompanionSingleVideoView> createState() => _CompanionSingleVideoViewState();
}

class _CompanionSingleVideoViewState extends State<CompanionSingleVideoView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideo);
  }

  @override
  void didUpdateWidget(covariant CompanionSingleVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideo);
      widget.controller.addListener(_onVideo);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideo);
    super.dispose();
  }

  void _onVideo() {
    if (!mounted) return;
    if (!widget.controller.value.isInitialized) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    if (viewport.isEmpty || !widget.controller.value.isInitialized) {
      return Positioned.fromRect(
        rect: viewport,
        child: const ColoredBox(color: Colors.black),
      );
    }

    return Positioned.fromRect(
      rect: viewport,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: kCompanionVideoFrame.width,
            height: kCompanionVideoFrame.height,
            child: VideoPlayer(widget.controller),
          ),
        ),
      ),
    );
  }
}
