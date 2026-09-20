import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('sqliteObjectOpensTableBrowser covers table and view', () {
    expect(sqliteObjectOpensTableBrowser(SqliteObjectKind.table), isTrue);
    expect(sqliteObjectOpensTableBrowser(SqliteObjectKind.view), isTrue);
  });

  testWidgets('Stay keeps the caller on the SQL session', (tester) async {
    var left = false;
    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
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
