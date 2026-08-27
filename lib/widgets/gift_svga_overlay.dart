import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svga/flutter_svga.dart';
import 'package:http/http.dart' as http;

import 'app_network_image.dart';

/// 全屏播一次礼物 SVGA，播完回调 [onFinished]。
class GiftSvgaOverlay extends StatefulWidget {
  const GiftSvgaOverlay({
    super.key,
    required this.url,
    required this.onFinished,
  });

  final String url;
  final VoidCallback onFinished;

  @override
  State<GiftSvgaOverlay> createState() => _GiftSvgaOverlayState();
}

class _GiftSvgaOverlayState extends State<GiftSvgaOverlay>
    with SingleTickerProviderStateMixin {
  late final SVGAAnimationController _controller;
  bool _ready = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = SVGAAnimationController(vsync: this);
    _controller.addStatusListener(_onStatus);
    _load();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finish();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  Future<MovieEntity> _decode(String url) async {
    final cached = await SVGACache.shared.getRawBytes(url);
    if (cached != null && cached.isNotEmpty) {
      return SVGAParser.shared.decodeFromBuffer(cached);
    }
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': kMediaRequestHeaders['User-Agent']!,
        'Accept': '*/*',
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
      throw Exception('svga http ${res.statusCode}');
    }
    final bytes = Uint8List.fromList(res.bodyBytes);
    await SVGACache.shared.putRawBytes(url, bytes);
    return SVGAParser.shared.decodeFromBuffer(bytes);
  }

  Future<void> _load() async {
    try {
      final video = await _decode(widget.url);
      if (!mounted) {
        video.dispose();
        return;
      }
      _controller.videoItem = video;
      setState(() => _ready = true);
      await _controller.forward();
    } catch (_) {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.transparent,
        child: SVGAImage(_controller, fit: BoxFit.contain),
      ),
    );
  }
}
