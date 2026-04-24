import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';

void main() {
  group('kSqlStatementTimeoutMenuItems', () {
    test('has seven entries with expected values', () {
      expect(kSqlStatementTimeoutMenuItems.length, 7);
      final values = kSqlStatementTimeoutMenuItems.map((e) => e.value).toList();
      expect(values, [null, 10, 30, 60, 120, 300, 600]);
    });
  });

  group('SqlStatementTimeoutDropdown', () {
    testWidgets('builds DropdownButton with current value', (tester) async {
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: SqlStatementTimeoutDropdown(
              value: 60,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(material.DropdownButton<int?>), findsOneWidget);
      final dd = tester.widget<material.DropdownButton<int?>>(
        find.byType(material.DropdownButton<int?>),
      );
      expect(dd.value, 60);
      expect(dd.onChanged, isNotNull);
    });

    testWidgets('disables changes when enabled is false', (tester) async {
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: SqlStatementTimeoutDropdown(
              value: 30,
              onChanged: (_) {},
              enabled: false,
            ),
          ),
        ),
      );

      final dd = tester.widget<material.DropdownButton<int?>>(
        find.byType(material.DropdownButton<int?>),
      );
      expect(dd.onChanged, isNull);
    });

    testWidgets('onChanged receives new selection', (tester) async {
      int? last;
      await tester.pumpWidget(
        material.MaterialApp(
          home: material.Scaffold(
            body: SqlStatementTimeoutDropdown(
              value: null,
              onChanged: (v) => last = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(material.DropdownButton<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 s').last);
      await tester.pumpAndSettle();

      expect(last, 30);
    });
  });
}
