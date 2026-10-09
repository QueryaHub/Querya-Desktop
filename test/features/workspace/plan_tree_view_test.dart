import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/plan_tree_view.dart';
import 'package:querya_desktop/features/workspace/query_plan.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('a click on a plan node shows every field it reported (#1164)',
      (t) async {
    final root = PlanNode(
      operation: 'Hash Join',
      cost: 500,
      children: [
        PlanNode(
          operation: 'Seq Scan',
          relation: 'orders',
          cost: 300,
          details: {'Startup Cost': '0.00', 'Filter': 'paid'},
        ),
      ],
    );
    await t.pumpWidget(queryaThemeTestShell(
      child: material.SizedBox(
        width: 600,
        height: 600,
        child: PlanTreeView(root: root),
      ),
    ));
    await t.pump();

    expect(find.text('Seq Scan'), findsOneWidget);
    expect(find.text('Filter'), findsNothing);

    await t.tap(find.text('Seq Scan'));
    await t.pump();
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('paid'), findsOneWidget);
    expect(find.text('Startup Cost'), findsOneWidget);

    // A second click closes the details again.
    await t.tap(find.text('Seq Scan'));
    await t.pump();
    expect(find.text('Filter'), findsNothing);
  });
}
