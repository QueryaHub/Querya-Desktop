import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';

import '../../support/querya_theme_test_shell.dart';

/// #1314: editing a connection whose extension or driver is missing says so.
ConnectionRow _row({String? extensionId, String type = 'clickhouse'}) =>
    ConnectionRow(
      id: 7,
      type: type,
      name: 'Warehouse',
      extensionId: extensionId,
      createdAt: '2026-01-01T00:00:00Z',
    );

void main() {
  group('driverForConnection', () {
    const a = DriverContribution(driverId: 'clickhouse', displayName: 'CH');
    const b = DriverContribution(driverId: 'duckdb', displayName: 'Duck');

    test('the driver of the row\'s type', () {
      expect(driverForConnection(_row(type: 'duckdb'), [a, b]), b);
      expect(driverForConnection(_row(type: 'ClickHouse'), [a, b]), a);
    });

    test('the only driver of an extension, whatever the row says', () {
      expect(driverForConnection(_row(type: 'legacy'), [a]), a);
    });

    test('never another driver of an extension that has several', () {
      expect(driverForConnection(_row(type: 'legacy'), [a, b]), isNull);
      expect(driverForConnection(_row(), const []), isNull);
    });
  });

  testWidgets('editing a connection of a missing extension explains it',
      (t) async {
    ConnectionRow? result = _row();
    await t.pumpWidget(queryaThemeTestShell(
      child: material.Builder(
        builder: (context) => material.TextButton(
          onPressed: () async => result = await promptEditConnection(
              context, _row(extensionId: 'acme.warehouse-driver')),
          child: const material.Text('edit'),
        ),
      ),
    ));

    await t.tap(find.text('edit'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(result, isNull);
    expect(find.textContaining('acme.warehouse-driver'), findsOneWidget);
    expect(find.textContaining('not installed or is disabled'),
        findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('an unknown connection type explains it too', (t) async {
    await t.pumpWidget(queryaThemeTestShell(
      child: material.Builder(
        builder: (context) => material.TextButton(
          onPressed: () => promptEditConnection(context, _row(type: 'cobol')),
          child: const material.Text('edit'),
        ),
      ),
    ));

    await t.tap(find.text('edit'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    // `cobol` is no built-in type and no extension has it.
    expect(find.textContaining('Unknown connection type "cobol"'),
        findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });
}
