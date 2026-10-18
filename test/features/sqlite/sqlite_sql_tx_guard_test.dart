import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show MaterialApp;
import '../../support/querya_theme_test_shell.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';

void main() {
  test('sqliteObjectOpensTableBrowser covers table and view', () {
    expect(sqliteObjectOpensTableBrowser(SqliteObjectKind.table), isTrue);
    expect(sqliteObjectOpensTableBrowser(SqliteObjectKind.view), isTrue);
  });

  testWidgets('Stay keeps the caller on the SQL session', (tester) async {
    var left = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: queryaDarkMaterialTheme,
        home: material.Builder(
          builder: (context) {
            return material.TextButton(
              onPressed: () async {
                left = await confirmLeaveOpenSqliteTransaction(context);
              },
              child: const material.Text('Go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Open transaction'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(left, isFalse);
  });
}
