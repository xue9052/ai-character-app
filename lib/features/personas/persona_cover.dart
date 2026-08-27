import 'package:flutter/material.dart';

import '../../widgets/app_network_image.dart';

export '../../widgets/app_network_image.dart'
    show
        kMediaRequestHeaders,
        AppNetworkImage,
        AppImageCacheManager,
        appNetworkImageProvider;

String? resolvePersonaCoverUrl(String baseUrl, String? coverUrl) {
  if (coverUrl == null || coverUrl.isEmpty) return null;
  if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
    return coverUrl;
  }
  final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final path = coverUrl.startsWith('/') ? coverUrl : '/$coverUrl';
  return '$b$path';
}

/// 与封面同规则：相对路径拼 baseUrl
String? resolvePersonaBackgroundUrl(String baseUrl, String? backgroundUrl) {
  return resolvePersonaCoverUrl(baseUrl, backgroundUrl);
}

Color parseHexColor(String hex, {int fallback = 0xFF1A221A}) {
  final s = hex.trim();
  if (s.length == 7 && s.startsWith('#')) {
    return Color(int.parse(s.substring(1), radix: 16) + 0xFF000000);
  }
  return Color(fallback);
}

class PersonaCoverAvatar extends StatelessWidget {
  const PersonaCoverAvatar({
    super.key,
    required this.baseUrl,
    this.coverUrl,
    required this.fallbackColor,
    required this.fallbackLabel,
    this.radius = 24,
  });

  final String baseUrl;
  final String? coverUrl;
  final Color fallbackColor;
  final String fallbackLabel;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = resolvePersonaCoverUrl(baseUrl, coverUrl);
    if (url != null) {
      return ClipOval(
        child: AppNetworkImage(
          url: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, __) => SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: ColoredBox(
              color: fallbackColor,
              child: Center(
                child: SizedBox(
                  width: radius * 0.7,
                  height: radius * 0.7,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: fallbackColor,
      child: Text(
        fallbackLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

class PersonaCoverBanner extends StatelessWidget {
  const PersonaCoverBanner({
    super.key,
    required this.baseUrl,
    this.coverUrl,
    required this.fallbackColor,
    required this.fallbackLabel,
    this.height = 200,
  });

  final String baseUrl;
  final String? coverUrl;
  final Color fallbackColor;
  final String fallbackLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = resolvePersonaCoverUrl(baseUrl, coverUrl);
    if (url != null) {
      return AppNetworkImage(
        url: url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      height: height,
      width: double.infinity,
      color: fallbackColor,
      alignment: Alignment.center,
      child: Text(
        fallbackLabel,
        style: const TextStyle(color: Colors.white, fontSize: 48),
      ),
    );
  }
}
