import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Flutter 默认 Dart UA 会被部分 COS/WAF 拦截（HTTP 451）
const kMediaRequestHeaders = <String, String>{
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

/// 磁盘 + 内存图片缓存（默认 Image.network 只有短时内存缓存）。
class AppImageCacheManager {
  AppImageCacheManager._();

  static const key = 'appImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );
}

ImageProvider appNetworkImageProvider(String url) {
  return CachedNetworkImageProvider(
    url,
    headers: kMediaRequestHeaders,
    cacheManager: AppImageCacheManager.instance,
  );
}

/// 带磁盘缓存的网络图；二次打开走本地，不必再走服务器。
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget Function(BuildContext context, String url)? placeholder;
  final Widget Function(BuildContext context, String url, Object error)?
      errorWidget;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: kMediaRequestHeaders,
      cacheManager: AppImageCacheManager.instance,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: placeholder ??
          (context, _) => ColoredBox(
                color: Colors.white12,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
      errorWidget: errorWidget ??
          (context, _, __) => const ColoredBox(
                color: Colors.white12,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
    );
  }
}
