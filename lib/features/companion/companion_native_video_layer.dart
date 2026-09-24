import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'companion_native_video_controller.dart';

/// Android Media3 全屏视频层（无封面静图，避免人物与 loop 片不一致）。
class CompanionNativeVideoLayer extends StatefulWidget {
  const CompanionNativeVideoLayer({
    super.key,
    required this.controller,
  });

  final CompanionNativeVideoController controller;

  @override
  State<CompanionNativeVideoLayer> createState() => _CompanionNativeVideoLayerState();
}

class _CompanionNativeVideoLayerState extends State<CompanionNativeVideoLayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant CompanionNativeVideoLayer oldWidget) {
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
    final error = widget.controller.error;

    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AndroidView(
              key: const ValueKey('companion_media3_view'),
              viewType: CompanionNativeVideoController.platformViewType,
              layoutDirection: TextDirection.ltr,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: widget.controller.attach,
            ),
            if (error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error, style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
