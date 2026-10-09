import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// Renders an SVG document to PNG bytes at [scale] times its own size. The PNG
/// is drawn from the same document the SVG export saves, so the two match.
Future<Uint8List> svgToPng(String svg, {double scale = 2}) async {
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  try {
    final width = (info.size.width * scale).ceil();
    final height = (info.size.height * scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('the PNG could not be encoded');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}
