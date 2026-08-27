import 'package:flutter/material.dart';

import 'app_network_image.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.emoji,
    required this.colorHex,
    this.imageUrl,
    this.image,
    this.radius = 28,
  });

  final String emoji;
  final String colorHex;
  final String? imageUrl;
  final ImageProvider? image;
  final double radius;

  Color get _color {
    var hex = colorHex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF5B7C99);
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider = image;
    final url = (imageUrl ?? '').trim();
    if (provider == null && url.isNotEmpty) {
      provider = appNetworkImageProvider(url);
    }
    if (provider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _color,
        backgroundImage: provider,
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _color,
      child: Text(emoji, style: TextStyle(fontSize: radius * 0.9)),
    );
  }
}
