import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

void main() {
  testWidgets('a table offers the Data | Relations switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate());
    expect(find.text('Relations'), findsOneWidget);
  });

  testWidgets('a view does not offer the switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate(), isView: true);
    expect(find.text('Relations'), findsNothing);
  });

  testWidgets('extension tables do not offer the switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate(),
        showRelations: false);
    expect(find.text('Relations'), findsNothing);
  });

  testWidgets('Relations shows the neighbourhood and Data keeps its place',
      (t) async {
    final state = await pumpGenericTableView(t, FakeTableDataDelegate());
    expect(find.byType(ErdView), findsNothing);

    state.selectView(1);
    await t.pump();
    await t.pump();
    expect(find.byType(ErdView), findsOneWidget);
    expect(find.byKey(const material.ValueKey('relations_depth_1')),
        findsOneWidget);

    await t.tap(find.byKey(const material.ValueKey('relations_depth_2')));
    await t.pump();
    expect(find.byKey(const material.ValueKey('relations_depth_2')),
        findsOneWidget);

    await t.tap(find.text('Data'));
    await t.pump();
    expect(find.byType(ErdView), findsOneWidget);
  });
}
