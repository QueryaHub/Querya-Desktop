import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/help/about_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('showAboutDialog', () {
    testWidgets('dialog shows app name, license, and actions', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showAboutDialog(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Querya'), findsOneWidget);
      expect(find.textContaining('Version'), findsOneWidget);
      expect(find.text('Licensed under the MIT License.'), findsOneWidget);
      expect(find.text('View repository'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close dismisses the dialog', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showAboutDialog(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Querya'), findsNothing);
    });
  });
}
