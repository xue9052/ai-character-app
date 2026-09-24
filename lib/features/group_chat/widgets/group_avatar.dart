import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../personas/persona_cover.dart';

/// 群头像。自定义图优先；否则按微信的方式把成员封面拼成正方形格子。
/// 两人左右并排并垂直居中，三人上一下二，避免把脸切成细条或横幅。
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.baseUrl,
    this.coverUrl = '',
    this.memberCovers = const [],
    this.radius = 26,
  });

  final String baseUrl;
  final String coverUrl;
  final List<String> memberCovers;
  final double radius;

  static const _plate = Color(0xFF16161C);

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final primary = coverUrl.trim();
    if (primary.isNotEmpty) {
      final url = resolvePersonaCoverUrl(baseUrl, primary);
      if (url != null) {
        return _frame(
          size,
          AppNetworkImage(
            url: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorWidget: (_, __, ___) => _collage(size),
          ),
        );
      }
    }
    return _collage(size);
  }

  Widget _frame(double size, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: ColoredBox(
        color: _plate,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }

  Widget _collage(double size) {
    final urls = memberCovers.where((u) => u.trim().isNotEmpty).take(4).toList();
    if (urls.isEmpty) {
      return _frame(
        size,
        Icon(
          Icons.groups_rounded,
          color: Colors.white.withValues(alpha: 0.7),
          size: size * 0.42,
        ),
      );
    }
    if (urls.length == 1) {
      return _frame(size, _tile(urls.first, size, size));
    }
    final cells = _layout(urls, size);
    return _frame(
      size,
      Stack(
        children: [
          for (final cell in cells)
            Positioned.fromRect(rect: cell.rect, child: _tile(cell.url, cell.rect.width, cell.rect.height)),
        ],
      ),
    );
  }

  /// 微信群头像：每张都是正方形，缝是底色而不是把图拉变形。
  List<_Cell> _layout(List<String> urls, double size) {
    final gap = (size * 0.04).clamp(1.0, 2.5);
    final pad = size * 0.08;
    final inner = size - pad * 2;
    Rect square(double x, double y, double w) => Rect.fromLTWH(x, y, w, w);

    if (urls.length == 2) {
      final w = (inner - gap) / 2;
      final y = (size - w) / 2;
      return [
        _Cell(urls[0], square(pad, y, w)),
        _Cell(urls[1], square(pad + w + gap, y, w)),
      ];
    }
    if (urls.length == 3) {
      final w = (inner - gap) / 2;
      final top = (size - (w * 2 + gap)) / 2;
      return [
        _Cell(urls[0], square((size - w) / 2, top, w)),
        _Cell(urls[1], square(pad, top + w + gap, w)),
        _Cell(urls[2], square(pad + w + gap, top + w + gap, w)),
      ];
    }
    final w = (inner - gap) / 2;
    final origin = (size - (w * 2 + gap)) / 2;
    return [
      _Cell(urls[0], square(origin, origin, w)),
      _Cell(urls[1], square(origin + w + gap, origin, w)),
      _Cell(urls[2], square(origin, origin + w + gap, w)),
      _Cell(urls[3], square(origin + w + gap, origin + w + gap, w)),
    ];
  }

  Widget _tile(String raw, double width, double height) {
    final url = resolvePersonaCoverUrl(baseUrl, raw);
    if (url == null) return const ColoredBox(color: _plate);
    return AppNetworkImage(
      url: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.25),
      errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.bgDarkElevated),
    );
  }
}

class _Cell {
  const _Cell(this.url, this.rect);

  final String url;
  final Rect rect;
}
