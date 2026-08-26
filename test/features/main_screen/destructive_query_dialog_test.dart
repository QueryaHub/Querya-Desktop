import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/features/main_screen/destructive_query_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('DestructiveQueryDialog', () {
    testWidgets('renders warning, detected operations, and disables confirm until acknowledged', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      bool? result;

      final inspection = DestructiveSqlDetector.inspect('DROP TABLE legacy_users;');

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showDestructiveQueryDialog(
                  context: context,
                  result: inspection,
                  sql: 'DROP TABLE legacy_users;',
                  connectionName: 'Production PostgreSQL',
                );
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Destructive Operation Detected'), findsOneWidget);
      expect(find.text('Target connection: Production PostgreSQL'), findsOneWidget);
      expect(find.text('DROP TABLE'), findsOneWidget);
      expect(find.text('DROP TABLE legacy_users;'), findsOneWidget);
      expect(find.text('Execute Destructive Statement'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Confirm button is disabled when checkbox is unchecked
      await tester.tap(find.text('Execute Destructive Statement'));
      await tester.pumpAndSettle();
      expect(result, isNull);

      // Check acknowledgment checkbox
      await tester.tap(find.byType(material.Checkbox));
      await tester.pumpAndSettle();

      // Now clicking confirm returns true and dismisses dialog
      await tester.tap(find.text('Execute Destructive Statement'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('shows Critical header for DROP DATABASE', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));

      final inspection = DestructiveSqlDetector.inspect('DROP DATABASE customer_records;');

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showDestructiveQueryDialog(
                context: context,
                result: inspection,
                sql: 'DROP DATABASE customer_records;',
              ),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Critical Destructive Operation'), findsOneWidget);
      expect(find.text('DROP DATABASE'), findsOneWidget);
    });

    testWidgets('Cancel button dismisses dialog with false', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      bool? result;

      final inspection = DestructiveSqlDetector.inspect('TRUNCATE logs;');

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showDestructiveQueryDialog(
                  context: context,
                  result: inspection,
                  sql: 'TRUNCATE logs;',
                );
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
