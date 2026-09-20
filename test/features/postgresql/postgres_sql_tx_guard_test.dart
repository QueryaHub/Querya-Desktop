import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_tx_guard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('postgresObjectOpensTableBrowser covers grid kinds only', () {
    expect(postgresObjectOpensTableBrowser(PostgresObjectKind.table), isTrue);
    expect(postgresObjectOpensTableBrowser(PostgresObjectKind.view), isTrue);
    expect(
      postgresObjectOpensTableBrowser(PostgresObjectKind.materializedView),
      isTrue,
    );
    expect(
        postgresObjectOpensTableBrowser(PostgresObjectKind.function), isFalse);
    expect(
        postgresObjectOpensTableBrowser(PostgresObjectKind.sequence), isFalse);
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
                left = await confirmLeaveOpenPostgresTransaction(context);
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

  testWidgets('Leave confirms abandoning the open transaction', (tester) async {
    var left = false;
    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        home: material.Builder(
          builder: (context) {
            return material.TextButton(
              onPressed: () async {
                left = await confirmLeaveOpenPostgresTransaction(context);
              },
              child: const material.Text('Go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(left, isTrue);
  });
}
