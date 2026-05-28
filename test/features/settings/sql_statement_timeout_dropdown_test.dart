import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  group('kSqlStatementTimeoutMenuEntries', () {
    test('has seven entries with expected values', () {
      expect(kSqlStatementTimeoutMenuEntries.length, 7);
      final values =
          kSqlStatementTimeoutMenuEntries.map((e) => e.value).toList();
      expect(values, [null, 10, 30, 60, 120, 300, 600]);
    });
  });

  group('SqlStatementTimeoutDropdown', () {
    testWidgets('builds DropdownMenu with current value', (tester) async {
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

      expect(find.byType(material.DropdownMenu<int?>), findsOneWidget);
      final menu = tester.widget<material.DropdownMenu<int?>>(
        find.byType(material.DropdownMenu<int?>),
      );
      expect(menu.initialSelection, 60);
      expect(menu.onSelected, isNotNull);
    });

    testWidgets('disables changes when enabled is false', (tester) async {
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

      final menu = tester.widget<material.DropdownMenu<int?>>(
        find.byType(material.DropdownMenu<int?>),
      );
      expect(menu.enabled, isFalse);
    });
  });
}
