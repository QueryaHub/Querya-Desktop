import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaSpinner', () {
    testWidgets('renders indicator with small preset (14px)', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaSpinner(
            size: QueryaSpinnerSize.sm,
          ),
        ),
      );

      final indicator = tester.widget<material.CircularProgressIndicator>(
        find.byType(material.CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, 2.0);

      final box = tester.widget<material.SizedBox>(
        find.ancestor(
          of: find.byType(material.CircularProgressIndicator),
          matching: find.byType(material.SizedBox),
        ),
      );
      expect(box.width, 14);
      expect(box.height, 14);
    });

    testWidgets('renders indicator with large preset (32px)', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaSpinner(
            size: QueryaSpinnerSize.lg,
          ),
        ),
      );

      final box = tester.widget<material.SizedBox>(
        find.ancestor(
          of: find.byType(material.CircularProgressIndicator),
          matching: find.byType(material.SizedBox),
        ),
      );
      expect(box.width, 32);
      expect(box.height, 32);
    });

    testWidgets('renders label alongside spinner when provided', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaSpinner(
            label: 'Executing query...',
          ),
        ),
      );

      expect(find.text('Executing query...'), findsOneWidget);
      expect(find.byType(material.CircularProgressIndicator), findsOneWidget);
    });
  });
}
