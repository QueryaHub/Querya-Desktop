import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_tree_indent_guide.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  test('QueryaTreeTokens expose UI-05 guide + header metrics', () {
    expect(QueryaTreeTokens.serversHeaderTop, 12);
    expect(QueryaTreeTokens.guideWidth, 1);
    expect(QueryaTreeTokens.guideInset, 8);
    expect(QueryaTreeTokens.guideAlpha, 0.15);
  });

  testWidgets('QueryaTreeIndentGuide pads child and paints at depth',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const QueryaTreeIndentGuide(
          depth: 2,
          child: SizedBox(width: 40, height: 28, child: Text('leaf')),
        ),
      ),
    );

    expect(find.byType(QueryaTreeIndentGuide), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('leaf'), findsOneWidget);

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(QueryaTreeIndentGuide),
        matching: find.byType(Padding),
      ).first,
    );
    expect(padding.padding.resolve(TextDirection.ltr).left, 32);
  });

  testWidgets('QueryaTreeIndentGuide depth 0 does not paint', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const QueryaTreeIndentGuide(
          depth: 0,
          child: Text('root'),
        ),
      ),
    );

    expect(find.text('root'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(QueryaTreeIndentGuide),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });
}
