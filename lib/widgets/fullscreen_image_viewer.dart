import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import 'app_network_image.dart';

/// 全屏查看图片：双指缩放 + 点击关闭。
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    this.url,
    this.bytes,
    this.httpHeaders,
    this.showSave = true,
  });

  final String? url;
  final Uint8List? bytes;
  final Map<String, String>? httpHeaders;
  final bool showSave;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  bool _saving = false;

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          messenger?.showSnackBar(
            const SnackBar(content: Text('需要相册权限才能保存')),
          );
          return;
        }
      }
      late final Uint8List data;
      if (widget.bytes != null) {
        data = widget.bytes!;
      } else {
        final file = await AppImageCacheManager.instance.getSingleFile(
          widget.url!,
          headers: {
            ...kMediaRequestHeaders,
            if (widget.httpHeaders != null) ...widget.httpHeaders!,
          },
        );
        data = await file.readAsBytes();
      }
      final name = 'img_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(data, name: name);
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('已保存到相册')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.contain)
        : AppNetworkImage(
            url: widget.url!,
            fit: BoxFit.contain,
            httpHeaders: widget.httpHeaders,
            placeholder: (_, __) => const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(child: image),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
          if (widget.showSave)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveToGallery,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                    label: Text(_saving ? '保存中…' : '保存到相册'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void openFullscreenImage(
  BuildContext context, {
  String? url,
  Uint8List? bytes,
  Map<String, String>? httpHeaders,
  bool showSave = true,
}) {
  if ((url == null || url.isEmpty) && bytes == null) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      pageBuilder: (_, __, ___) => FullscreenImageViewer(
        url: url,
        bytes: bytes,
        httpHeaders: httpHeaders,
        showSave: showSave,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}
