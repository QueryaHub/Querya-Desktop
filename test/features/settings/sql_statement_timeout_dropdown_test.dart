import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  group('kSqlStatementTimeoutMenuItems', () {
    test('has seven entries with expected values', () {
      expect(kSqlStatementTimeoutMenuItems.length, 7);
      final values = kSqlStatementTimeoutMenuItems.map((e) => e.value).toList();
      expect(values, [null, 10, 30, 60, 120, 300, 600]);
    });
  });

  group('SqlStatementTimeoutDropdown', () {
    testWidgets('builds MenuAnchor with current value', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SqlStatementTimeoutDropdown(
              value: 60,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(material.MenuAnchor), findsOneWidget);
      expect(find.text('60 s'), findsOneWidget);
    });

    testWidgets('disables menu when enabled is false', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: SqlStatementTimeoutDropdown(
              value: 30,
              onChanged: (_) {},
              enabled: false,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('30 s'));
      await tester.pumpAndSettle();

      expect(find.text('10 s'), findsNothing);
    });
  });
}
