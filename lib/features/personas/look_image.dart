import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 从形象长图中间裁出正方形头像（对齐猫箱：整图作立绘/背景，中心方块作头像）
Future<Uint8List> centerSquareAvatarBytes(
  Uint8List source, {
  int maxSide = 768,
}) async {
  final codec = await ui.instantiateImageCodec(source);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final w = img.width;
  final h = img.height;
  if (w <= 0 || h <= 0) {
    throw StateError('无效图片');
  }

  final side = w < h ? w : h;
  final left = (w - side) / 2.0;
  final top = (h - side) / 2.0;
  final outSide = side > maxSide ? maxSide : side;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final src = Rect.fromLTWH(left, top, side.toDouble(), side.toDouble());
  final dst = Rect.fromLTWH(0, 0, outSide.toDouble(), outSide.toDouble());
  canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  final picture = recorder.endRecording();
  final out = await picture.toImage(outSide, outSide);
  final bd = await out.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  out.dispose();
  if (bd == null) {
    throw StateError('裁剪失败');
  }
  return bd.buffer.asUint8List();
}
