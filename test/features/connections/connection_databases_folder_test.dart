import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_databases_folder.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  final conn = ConnectionRow(
    type: 'postgresql',
    name: 'pg',
    host: '127.0.0.1',
    port: 5432,
    createdAt: DateTime.utc(2025).toIso8601String(),
    id: 1,
  );

  testWidgets('ConnectionDatabasesFolder collapses and expands children',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Material(
          child: ConnectionDatabasesFolder(
            connection: conn,
            databaseCount: 2,
            child: const material.Column(
              children: [
                material.Text('db_alpha'),
                material.Text('db_beta'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Databases (2)'), findsOneWidget);
    expect(find.text('db_alpha'), findsOneWidget);
    expect(find.text('db_beta'), findsOneWidget);

    await tester.tap(find.text('Databases (2)'));
    await tester.pumpAndSettle();

    expect(find.text('db_alpha'), findsNothing);
    expect(find.text('db_beta'), findsNothing);

    await tester.tap(find.text('Databases (2)'));
    await tester.pumpAndSettle();

    expect(find.text('db_alpha'), findsOneWidget);
    expect(find.text('db_beta'), findsOneWidget);
  });

  testWidgets(
      'ConnectionDatabasesFolder keeps the same chrome for redis-style use',
      (tester) async {
    final redis = ConnectionRow(
      type: 'redis',
      name: 'redis',
      host: '127.0.0.1',
      port: 6379,
      createdAt: DateTime.utc(2025).toIso8601String(),
      id: 2,
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Material(
          child: ConnectionDatabasesFolder(
            connection: redis,
            databaseCount: 16,
            child: const Text('db0'),
          ),
        ),
      ),
    );

    expect(find.text('Databases (16)'), findsOneWidget);
    expect(find.text('db0'), findsOneWidget);
    expect(find.byType(QueryaAnimatedExpand), findsOneWidget);
  });
}
