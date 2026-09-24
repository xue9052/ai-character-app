import 'package:flutter/material.dart';

import '../personas/persona_cover.dart';
import '../personas/persona_presets.dart';

/// 聊天 / 语音通话共用背景：专用背景图 → 封面图 → 预设渐变。
class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({
    super.key,
    required this.baseUrl,
    this.backgroundKey,
    this.backgroundUrl,
    this.coverUrl,
  });

  final String baseUrl;
  final String? backgroundKey;
  final String? backgroundUrl;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = resolvePersonaBackgroundUrl(baseUrl, backgroundUrl) ??
        resolvePersonaCoverUrl(baseUrl, coverUrl);
    if (url != null && url.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(
            url: url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorWidget: (_, __, ___) {
              final cover = resolvePersonaCoverUrl(baseUrl, coverUrl);
              if (cover != null && cover.isNotEmpty && cover != url) {
                return AppNetworkImage(
                  url: cover,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                  errorWidget: (_, __, ___) =>
                      ChatPresetBackdrop(backgroundKey: backgroundKey),
                );
              }
              return ChatPresetBackdrop(backgroundKey: backgroundKey);
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14101014),
                  Color(0x08101014),
                  Color(0x26101014),
                  Color(0x59101014),
                  Color(0x8A101014),
                ],
                stops: [0.0, 0.32, 0.55, 0.78, 1.0],
              ),
            ),
          ),
          CustomPaint(painter: ChatVignettePainter()),
        ],
      );
    }
    return ChatPresetBackdrop(backgroundKey: backgroundKey);
  }
}

class ChatPresetBackdrop extends StatelessWidget {
  const ChatPresetBackdrop({this.backgroundKey});

  final String? backgroundKey;

  @override
  Widget build(BuildContext context) {
    Map<String, String>? preset;
    for (final p in kBackgroundPresets) {
      if (p['key'] == backgroundKey) {
        preset = p;
        break;
      }
    }
    preset ??= kBackgroundPresets.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            parseHexColor(preset['color_from']!, fallback: 0xFF1A1A2E),
            parseHexColor(preset['color_mid']!, fallback: 0xFF12121F),
            parseHexColor(preset['color_to']!, fallback: 0xFF0A0A14),
          ],
        ),
      ),
      child: CustomPaint(painter: ChatVignettePainter()),
    );
  }
}

class ChatVignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 1.15,
        colors: [
          const Color(0xFF000000).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
