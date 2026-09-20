import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_tx_guard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('mysqlObjectOpensTableBrowser covers table and view only', () {
    expect(mysqlObjectOpensTableBrowser(MysqlObjectKind.table), isTrue);
    expect(mysqlObjectOpensTableBrowser(MysqlObjectKind.view), isTrue);
    expect(mysqlObjectOpensTableBrowser(MysqlObjectKind.procedure), isFalse);
    expect(mysqlObjectOpensTableBrowser(MysqlObjectKind.function), isFalse);
  });

  test('mysqlSqlToolbarTxLabel matches Postgres wording', () {
    expect(mysqlSqlToolbarTxLabel(null), 'Transaction: —');
    expect(mysqlSqlToolbarTxLabel(true), 'Transaction: open');
    expect(mysqlSqlToolbarTxLabel(false), 'Transaction: none');
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
                left = await confirmLeaveOpenMysqlTransaction(context);
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
