import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/export/svg_png.dart';

void main() {
  testWidgets('an SVG rasterises to a PNG at its size times the scale (#1163)',
      (t) async {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10">'
        '<rect width="20" height="10" fill="#ff0000"/></svg>';
    final bytes = await t.runAsync(() => svgToPng(svg, scale: 2));

    expect(bytes, isNotNull);
    final png = bytes!;
    // The PNG signature, then the IHDR width and height (big-endian).
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    int u32(int at) =>
        (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3];
    expect(u32(16), 40);
    expect(u32(20), 20);
  });
}
