import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_stage.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_workspace.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final connection = MongoConnection(id: 1, name: 'e2e', host: 'localhost');

  const match = MongoAggregationStage(
    id: 'stage_1',
    operator: r'$match',
    queryText: '{"status": "A"}',
  );
  const group = MongoAggregationStage(
    id: 'stage_2',
    operator: r'$group',
    queryText: r'{"_id": "$customer", "total": {"$sum": "$amount"}}',
  );

  Future<void> open(WidgetTester tester,
      List<MongoAggregationStage> stages) async {
    await tester.binding.setSurfaceSize(const material.Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        data: QueryaTheme.darkDefault,
        child: material.SizedBox(
          width: 1400,
          height: 800,
          child: MongoAggregationWorkspace(
            connection: connection,
            database: 'shop',
            collection: 'orders',
            initialStages: stages,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a \$match + \$group pipeline is assembled and exported',
      timeout: _timeout, (tester) async {
    await open(tester, [match, group]);

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('2 stages'), findsOneWidget);

    await tester.tap(find.text('Export Code'));
    await tester.pumpAndSettle();

    expect(find.text('Export Aggregation Pipeline'), findsOneWidget);
    expect(find.textContaining(r'$match'), findsWidgets);
    expect(find.textContaining(r'$group'), findsWidgets);
    expect(find.textContaining('orders'), findsWidgets);
  });

  testWidgets('a broken second stage names itself and does not run',
      timeout: _timeout, (tester) async {
    await open(tester, [
      match,
      group.copyWith(queryText: '{ "_id": '),
    ]);

    final run = find.text('Run Pipeline');
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();

    expect(find.textContaining('Stage #2'), findsOneWidget);
    expect(find.textContaining('syntax error'), findsOneWidget);
    expect(find.text('No Documents Yet'), findsOneWidget);
  });

  testWidgets('a disabled stage is counted out of the active ones',
      timeout: _timeout, (tester) async {
    await open(tester, [match, group]);

    await tester.tap(find.byType(material.Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('1 / 2 active'), findsOneWidget);
  });
}
