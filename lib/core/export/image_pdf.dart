import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// Paper of a PDF export, in points (1/72 in), portrait.
enum PdfPaper {
  a4(595.28, 841.89),
  a3(841.89, 1190.55);

  const PdfPaper(this.width, this.height);
  final double width;
  final double height;
}

/// Where a picture of [content] size goes on a [paper] page: the page (landscape
/// when the picture is wider than tall), the picture fitted inside the margin
/// and centred, and the raster density that gives it about 200 dpi.
class PdfPagePlan {
  const PdfPagePlan({
    required this.pageWidth,
    required this.pageHeight,
    required this.x,
    required this.y,
    required this.drawWidth,
    required this.drawHeight,
    required this.pixelRatio,
  });

  /// [x] and [y] are the top-left of the picture from the page's top-left.
  final double pageWidth;
  final double pageHeight;
  final double x;
  final double y;
  final double drawWidth;
  final double drawHeight;

  /// Raster pixels per unit of [content]; the longest raster side is capped.
  final double pixelRatio;

  static const double margin = 28;
  static const int maxSide = 4096;
  static const double dpi = 200;

  factory PdfPagePlan.fit(ui.Size content, PdfPaper paper) {
    final landscape = content.width > content.height;
    final pw = landscape ? paper.height : paper.width;
    final ph = landscape ? paper.width : paper.height;
    final cw = math.max(1.0, content.width), ch = math.max(1.0, content.height);
    final s = math.min((pw - 2 * margin) / cw, (ph - 2 * margin) / ch);
    final dw = cw * s, dh = ch * s;
    final wanted = s * dpi / 72;
    final cap = maxSide / math.max(cw, ch);
    return PdfPagePlan(
      pageWidth: pw,
      pageHeight: ph,
      x: (pw - dw) / 2,
      y: (ph - dh) / 2,
      drawWidth: dw,
      drawHeight: dh,
      pixelRatio: math.min(wanted, cap),
    );
  }
}

/// A one-page PDF that shows an RGB image (8 bits a channel, [rgb] of
/// `width * height * 3` bytes) at [plan]. Hand-written: one catalog, one page,
/// one Flate-compressed image and a content stream that places it.
Uint8List buildImagePdf({
  required int width,
  required int height,
  required Uint8List rgb,
  required PdfPagePlan plan,
}) {
  assert(rgb.length == width * height * 3);
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  void ascii(String s) => out.add(latin1.encode(s));
  void object(int n, String dict, [Uint8List? stream]) {
    offsets.add(out.length);
    ascii('$n 0 obj\n');
    if (stream == null) {
      ascii('$dict\nendobj\n');
    } else {
      ascii('${dict.replaceFirst('>>', '/Length ${stream.length} >>')}\n'
          'stream\n');
      out.add(stream);
      ascii('\nendstream\nendobj\n');
    }
  }

  String n(double v) => v.toStringAsFixed(2);
  ascii('%PDF-1.4\n');
  out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  object(
      3,
      '<< /Type /Page /Parent 2 0 R '
      '/MediaBox [0 0 ${n(plan.pageWidth)} ${n(plan.pageHeight)}] '
      '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>');
  object(
      4,
      '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
      '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode >>',
      Uint8List.fromList(ZLibCodec(level: 6).encode(rgb)));
  // PDF's origin is the bottom-left corner of the page.
  final bottom = plan.pageHeight - plan.y - plan.drawHeight;
  object(
      5,
      '<< >>',
      Uint8List.fromList(latin1.encode('q ${n(plan.drawWidth)} 0 0 '
          '${n(plan.drawHeight)} ${n(plan.x)} ${n(bottom)} cm /Im0 Do Q')));

  final xref = out.length;
  ascii('xref\n0 6\n0000000000 65535 f \n');
  for (final o in offsets) {
    ascii('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  ascii('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}

/// Renders an SVG document to a one-page PDF on [paper]: the picture fitted
/// to the page, as a raster of about 200 dpi.
Future<Uint8List> svgToPdf(String svg, {PdfPaper paper = PdfPaper.a4}) async {
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  try {
    final plan = PdfPagePlan.fit(info.size, paper);
    final width = math.max(1, (info.size.width * plan.pixelRatio).ceil());
    final height = math.max(1, (info.size.height * plan.pixelRatio).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    // White under the picture: the PDF has no alpha.
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.scale(width / info.size.width, height / info.size.height);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData();
        if (data == null) throw StateError('the PDF image could not be read');
        final rgba = data.buffer.asUint8List();
        final rgb = Uint8List(width * height * 3);
        for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
          rgb[j] = rgba[i];
          rgb[j + 1] = rgba[i + 1];
          rgb[j + 2] = rgba[i + 2];
        }
        return buildImagePdf(
            width: width, height: height, rgb: rgb, plan: plan);
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
