import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/tree_load_error.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('TreeLoadError shows message and retry', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: TreeLoadError(
          message: 'connection refused',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('connection refused'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retried, isTrue);
  });

  testWidgets('TreeLoadError title row uses error icon', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const TreeLoadError(
          title: 'Could not load',
          message: 'timeout',
          showTitleRow: true,
        ),
      ),
    );

    expect(find.text('Could not load'), findsOneWidget);
    expect(find.byIcon(material.Icons.error_outline_rounded), findsOneWidget);
  });
}
