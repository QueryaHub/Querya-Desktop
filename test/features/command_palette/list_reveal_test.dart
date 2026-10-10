import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/command_palette/list_reveal.dart';

void main() {
  // 10 rows of 40 px in a 100 px viewport, 4 px leading and 8 px trailing.
  double? reveal(int index, double offset) => revealOffsetForItem(
        index: index,
        itemExtent: 40,
        offset: offset,
        viewportExtent: 100,
        leadingPadding: 4,
        trailingPadding: 8,
      );

  test('a fully visible row needs no scroll', () {
    expect(reveal(0, 0), isNull);
    expect(reveal(1, 0), isNull);
  });

  test('a row below the viewport scrolls it up to the bottom edge', () {
    // Row 2 spans 84..124; the viewport shows 0..100.
    expect(reveal(2, 0), 124 + 8 - 100);
  });

  test('a row above the viewport scrolls back to it', () {
    // Row 3 spans 124..164; the viewport shows 150..250.
    expect(reveal(3, 150), 120);
  });

  test('the first row scrolls to the very top', () {
    expect(reveal(0, 60), 0);
  });

  test('a partly visible row is revealed', () {
    // Row 2 spans 84..124; the viewport shows 20..120 → bottom 4 px hidden.
    expect(reveal(2, 20), 124 + 8 - 100);
  });
}
