import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../chat/chat_backdrop.dart';
import '../../personas/persona_cover.dart';

/// 群聊背景：2–3 个成员封面拼贴（全屏），叠加与私聊一致的暗角渐变。
class GroupChatBackdrop extends StatelessWidget {
  const GroupChatBackdrop({
    super.key,
    required this.baseUrl,
    this.memberCovers = const [],
  });

  final String baseUrl;
  final List<String> memberCovers;

  @override
  Widget build(BuildContext context) {
    final urls = memberCovers
        .map((u) => resolvePersonaCoverUrl(baseUrl, u))
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .take(3)
        .toList();
    if (urls.isEmpty) {
      return const ChatPresetBackdrop();
    }
    if (urls.length == 1) {
      return ChatBackdrop(baseUrl: baseUrl, coverUrl: memberCovers.first);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _Collage(urls: urls),
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
}

class _Collage extends StatelessWidget {
  const _Collage({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.length == 2) {
      return Row(
        children: [
          Expanded(child: _tile(urls[0])),
          const SizedBox(width: 2),
          Expanded(child: _tile(urls[1])),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 5, child: _tile(urls[0])),
        const SizedBox(width: 2),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(child: _tile(urls[1])),
              const SizedBox(height: 2),
              Expanded(child: _tile(urls[2])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(String url) {
    return AppNetworkImage(
      url: url,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.15),
      width: double.infinity,
      height: double.infinity,
      errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.bgDark),
    );
  }
}
