import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/export/image_pdf.dart';

/// #1285: the hand-written PDF.
void main() {
  group('page plan', () {
    test('a wide picture gets a landscape page, fitted inside the margin', () {
      final plan = PdfPagePlan.fit(const Size(2000, 1000), PdfPaper.a4);
      expect(plan.pageWidth, closeTo(841.89, 0.01));
      expect(plan.pageHeight, closeTo(595.28, 0.01));
      expect(plan.drawWidth, closeTo(841.89 - 2 * PdfPagePlan.margin, 0.01));
      expect(plan.drawHeight / plan.drawWidth, closeTo(0.5, 0.001));
      // Centred.
      expect(plan.x, closeTo(PdfPagePlan.margin, 0.01));
      expect(plan.y + plan.drawHeight / 2, closeTo(plan.pageHeight / 2, 0.01));
    });

    test('a tall picture gets a portrait page, A3 is larger than A4', () {
      final a4 = PdfPagePlan.fit(const Size(500, 1500), PdfPaper.a4);
      final a3 = PdfPagePlan.fit(const Size(500, 1500), PdfPaper.a3);
      expect(a4.pageHeight, greaterThan(a4.pageWidth));
      expect(a3.pageWidth, greaterThan(a4.pageWidth));
      expect(a3.drawHeight, greaterThan(a4.drawHeight));
    });

    test('the raster is about 200 dpi and never over the side cap', () {
      final small = PdfPagePlan.fit(const Size(800, 500), PdfPaper.a4);
      // Pixels per point of the page is dpi / 72.
      expect(small.pixelRatio * 800 / small.drawWidth, closeTo(200 / 72, 0.01));
      final huge = PdfPagePlan.fit(const Size(40000, 20000), PdfPaper.a3);
      expect(40000 * huge.pixelRatio, lessThanOrEqualTo(PdfPagePlan.maxSide));
    });
  });

  test('the PDF has a catalog, one page, an image and a valid xref', () {
    const w = 4, h = 3;
    final bytes = buildImagePdf(
      width: w,
      height: h,
      rgb: Uint8List(w * h * 3)..fillRange(0, w * h * 3, 200),
      plan: PdfPagePlan.fit(const Size(400, 300), PdfPaper.a4),
    );
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF-1.4'));
    expect(text.trimRight(), endsWith('%%EOF'));
    expect(text, contains('/Type /Catalog'));
    expect(text, contains('/Count 1'));
    expect(text, contains('/MediaBox [0 0 841.89 595.28]'));
    expect(text, contains('/Width 4 /Height 3'));
    expect(text, contains('/Filter /FlateDecode'));
    expect(text, contains('/Im0 Do'));

    // Every xref entry points at its object.
    final start = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
    expect(text.substring(start), startsWith('xref\n0 6\n'));
    final entries = RegExp(r'(\d{10}) 00000 n ')
        .allMatches(text.substring(start))
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(entries, hasLength(5));
    for (var i = 0; i < entries.length; i++) {
      expect(text.substring(entries[i]), startsWith('${i + 1} 0 obj'));
    }
  });
}
