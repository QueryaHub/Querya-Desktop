import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/table_view_command_bridge.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/results_tab.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

void main() {
  setUp(() => TableViewCommandBridge.instance.resetForTest());

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
    // Offstage, not gone: the neighbourhood and the grid both stay alive.
    expect(find.byType(ErdView, skipOffstage: false), findsOneWidget);
    expect(find.byType(ResultsTab, skipOffstage: false), findsOneWidget);
  });

  testWidgets('the palette switches a table between Data and Relations',
      (t) async {
    final bridge = TableViewCommandBridge.instance;
    await pumpGenericTableView(t, FakeTableDataDelegate());
    expect(bridge.isActive, isTrue);

    bridge.invokeSelectView(1);
    await t.pump();
    await t.pump();
    expect(find.byType(ErdView), findsOneWidget);

    bridge.invokeSelectView(0);
    await t.pump();
    expect(find.text('Relations'), findsOneWidget);
  });

  testWidgets('a view leaves nothing for the palette to switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate(), isView: true);
    expect(TableViewCommandBridge.instance.isActive, isFalse);
  });

  testWidgets('a table asked to open in Relations starts there', (t) async {
    TableViewCommandBridge.instance.requestViewForNextTable(1);
    await pumpGenericTableView(t, FakeTableDataDelegate());
    await t.pump();
    expect(find.byType(ErdView), findsOneWidget);
    // The request is used once.
    expect(TableViewCommandBridge.instance.takePendingView(), isNull);
  });

  testWidgets('a view ignores a Relations request', (t) async {
    TableViewCommandBridge.instance.requestViewForNextTable(1);
    await pumpGenericTableView(t, FakeTableDataDelegate(), isView: true);
    await t.pump();
    expect(find.byType(ErdView), findsNothing);
  });
}
