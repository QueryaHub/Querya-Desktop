import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_text.dart';

import '../../support/querya_theme_test_shell.dart';

material.TextStyle _styleOf(WidgetTester tester, String text) {
  final context = tester.element(find.text(text));
  return material.DefaultTextStyle.of(context).style;
}

void main() {
  group('QueryaTextStyles', () {
    testWidgets('sizes and weights go through the default text style',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Column(
            children: [
              const material.Text('x').xSmall(),
              const material.Text('s').small(),
              const material.Text('b').base(),
              const material.Text('l').large(),
              const material.Text('sb').semiBold(),
              const material.Text('bo').bold(),
              const material.Text('me').medium(),
            ],
          ),
        ),
      );

      expect(_styleOf(tester, 'x').fontSize, 12);
      expect(_styleOf(tester, 's').fontSize, 14);
      expect(_styleOf(tester, 'b').fontSize, 16);
      expect(_styleOf(tester, 'l').fontSize, 18);
      expect(_styleOf(tester, 'sb').fontWeight, material.FontWeight.w600);
      expect(_styleOf(tester, 'bo').fontWeight, material.FontWeight.w700);
      expect(_styleOf(tester, 'me').fontWeight, material.FontWeight.w500);
    });

    testWidgets('modifiers chain and keep each other', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Text('chain').semiBold().small(),
        ),
      );

      final style = _styleOf(tester, 'chain');
      expect(style.fontSize, 14);
      expect(style.fontWeight, material.FontWeight.w600);
    });

    testWidgets('muted and foreground use the colour scheme', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Column(
            children: [
              const material.Text('quiet').muted(),
              const material.Text('loud').foreground(),
            ],
          ),
        ),
      );

      expect(
        _styleOf(tester, 'quiet').color,
        isNot(_styleOf(tester, 'loud').color),
      );
    });
  });
}
