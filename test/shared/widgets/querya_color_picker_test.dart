import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_color_picker.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  test('hex round trip, with and without alpha', () {
    const c = material.Color(0x80FF8800);
    expect(QueryaColorPicker.toHex(c), '#80FF8800');
    expect(QueryaColorPicker.toHex(c, alpha: false), '#FF8800');
    expect(QueryaColorPicker.parseHex('#80ff8800'), c);
    expect(QueryaColorPicker.parseHex('ff8800'), const material.Color(0xFFFF8800));
    expect(QueryaColorPicker.parseHex('#ff88'), isNull);
    expect(QueryaColorPicker.parseHex('nothex'), isNull);
  });

  testWidgets('typing a hex reports that colour', (t) async {
    material.Color? seen;
    await t.pumpWidget(queryaThemeTestShell(
      child: material.Material(
        child: QueryaColorPicker(
          value: const material.Color(0xFF000000),
          onChanged: (c) => seen = c,
        ),
      ),
    ));
    await t.enterText(find.byType(material.TextField), '#FF8800');
    expect(seen, const material.Color(0xFFFF8800));
  });
}
