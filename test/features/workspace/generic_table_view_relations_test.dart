import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/table_view_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';
import 'package:querya_desktop/features/workspace/results_tab.dart';
import 'package:querya_desktop/features/workspace/table_data_delegate.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

/// A catalog around `users`: it references `orgs`, `orders` references it,
/// `orgs` references `regions` (two keys away), `unrelated` has no keys.
TableDataPage _catalog(String sql) {
  for (final d in SqlDialect.values) {
    if (sql == ErdCatalog.foreignKeysSql(d)) {
      return const TableDataPage(columns: ['t', 'c', 'rt', 'rc'], rows: [
        ['orders', 'user_id', 'users', 'id'],
        ['users', 'org_id', 'orgs', 'id'],
        ['orgs', 'region_id', 'regions', 'id'],
      ]);
    }
    if (sql == ErdCatalog.columnsSql(d) ||
        sql == ErdCatalog.columnsSql(d, schema: 'public')) {
      return const TableDataPage(columns: ['t', 'c', 'ty', 'pk'], rows: [
        ['users', 'id', 'integer', '1'],
        ['users', 'org_id', 'integer', '0'],
        ['orders', 'id', 'integer', '1'],
        ['orders', 'user_id', 'integer', '0'],
        ['orgs', 'id', 'integer', '1'],
        ['orgs', 'region_id', 'integer', '0'],
        ['regions', 'id', 'integer', '1'],
        ['unrelated', 'id', 'integer', '1'],
      ]);
    }
  }
  return const TableDataPage(columns: [], rows: []);
}

Future<void> _settleDiagram(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

Finder _card(String table) =>
    find.byKey(material.ValueKey('erd_table_$table'));

Iterable<double> _opacityOf(WidgetTester t, String table) =>
    t.widgetList<material.Opacity>(find.ancestor(
      of: _card(table),
      matching: find.byType(material.Opacity),
    )).map((o) => o.opacity);

void main() {
  setUp(() => TableViewCommandBridge.instance.resetForTest());

  for (final (dialect, schema) in [
    (SqlDialect.postgres, 'public'),
    // MySQL passes the database as the schema; its catalog names are bare.
    (SqlDialect.mysql, 'shop'),
    (SqlDialect.sqlite, null),
  ]) {
    testWidgets(
        '${dialect.name}: referenced tables sit left, referencing ones right',
        (t) async {
      final state = await pumpGenericTableView(
        t,
        FakeTableDataDelegate(onCustomSql: _catalog),
        dialect: dialect,
        schema: schema,
      );
      state.selectView(1);
      await _settleDiagram(t);

      expect(_card('users'), findsOneWidget);
      expect(_card('orgs'), findsOneWidget);
      expect(_card('orders'), findsOneWidget);
      expect(_card('unrelated'), findsNothing);
      expect(_card('regions'), findsNothing, reason: 'two keys away at depth 1');

      double x(String table) => t.getTopLeft(_card(table)).dx;
      expect(x('orgs'), lessThan(x('users')));
      expect(x('users'), lessThan(x('orders')));
    });
  }

  testWidgets('depth 2 adds the tables two keys away; the table stays picked',
      (t) async {
    final state = await pumpGenericTableView(
        t, FakeTableDataDelegate(onCustomSql: _catalog));
    state.selectView(1);
    await _settleDiagram(t);
    expect(_card('regions'), findsNothing);

    await t.tap(find.byKey(const material.ValueKey('relations_depth_2')));
    await _settleDiagram(t);
    expect(_card('regions'), findsOneWidget);
    // The browsed table is picked: its neighbours stay clear, the table two
    // keys away fades.
    expect(_opacityOf(t, 'users'), isNot(contains(0.35)));
    expect(_opacityOf(t, 'orgs'), isNot(contains(0.35)));
    expect(_opacityOf(t, 'regions'), contains(0.35));
  });

  testWidgets('a double click on a neighbour asks to open it', (t) async {
    final opened = <String>[];
    final state = await pumpGenericTableView(
      t,
      FakeTableDataDelegate(onCustomSql: _catalog),
      onOpenNeighbour: opened.add,
    );
    state.selectView(1);
    await _settleDiagram(t);

    await t.tap(_card('orders'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(_card('orders'));
    await t.pump(const Duration(milliseconds: 400));
    expect(opened, ['orders']);
  });

  testWidgets(
      'a double click on a neighbour opens it through the host, in Relations',
      (t) async {
    final opened = <QueryaSchemaObject>[];
    final state = await pumpGenericTableView(
      t,
      FakeTableDataDelegate(onCustomSql: _catalog),
      onOpenSchemaObject: opened.add,
    );
    state.selectView(1);
    await _settleDiagram(t);

    await t.tap(_card('orders'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(_card('orders'));
    await t.pump(const Duration(milliseconds: 400));

    expect(opened.map((o) => (o.name, o.schema, o.kind)),
        [('orders', 'public', QueryaSchemaObjectKind.table)]);
    // The neighbour's tab starts in Relations, like the table it came from.
    expect(TableViewCommandBridge.instance.takePendingView(), 1);
  });

  testWidgets('Data, Relations, Data keeps staged edits', (t) async {
    final delegate = FakeTableDataDelegate(onCustomSql: _catalog);
    final state = await pumpGenericTableView(t, delegate);
    state.toggleEditMode();
    await t.pumpAndSettle();
    final buffer = state.stagingBuffer!;
    buffer.setCell(0, 1, 'Alicia');
    await t.pump();
    expect(state.isDirty, isTrue);

    state.selectView(1);
    await _settleDiagram(t);
    state.selectView(0);
    await t.pump();

    expect(identical(state.stagingBuffer, buffer), isTrue);
    expect(state.isDirty, isTrue);
    expect(buffer.effectiveRows[0][1], 'Alicia');
  });

  testWidgets('Data, Relations, Data keeps the page without reloading it',
      (t) async {
    final delegate = FakeTableDataDelegate(onCustomSql: _catalog);
    final state = await pumpGenericTableView(t, delegate, limit: 2);
    state.goToNextPage();
    await t.pumpAndSettle();
    expect(state.offset, 2);
    final loads = delegate.pagesLoaded.length;

    state.selectView(1);
    await _settleDiagram(t);
    state.selectView(0);
    await t.pump();

    expect(state.offset, 2);
    expect(delegate.pagesLoaded.length, loads);
  });

  testWidgets('Data, Relations, Data keeps the quick filter', (t) async {
    final state = await pumpGenericTableView(
        t, FakeTableDataDelegate(onCustomSql: _catalog));
    await t.tap(find.byTooltip('Toggle Quick Filter'));
    await t.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(DataGridFilterBar),
      matching: find.byType(material.TextField),
    );
    await t.enterText(field, 'Bob');
    // Let the filter bar's debounce fire.
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsWidgets);

    state.selectView(1);
    await _settleDiagram(t);
    state.selectView(0);
    await t.pumpAndSettle();

    expect(t.widget<material.TextField>(field).controller!.text, 'Bob');
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsWidgets);
  });

  testWidgets('a table offers the Data | Relations switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate());
    expect(find.text('Relations'), findsOneWidget);
  });

  testWidgets('a view does not offer the switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate(), isView: true);
    expect(find.text('Relations'), findsNothing);
  });

  testWidgets('a materialized view does not offer the switch', (t) async {
    await pumpGenericTableView(t, FakeTableDataDelegate(),
        isMaterializedView: true);
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

  testWidgets('closing a table tab releases its delegate without cancelling it',
      (t) async {
    final delegate = FakeTableDataDelegate();
    await pumpGenericTableView(t, delegate);
    await t.pumpWidget(const material.SizedBox());
    await t.pump();
    // The session is shared with other views: closing must not interrupt it.
    expect(delegate.cancelCount, 0);
    expect(delegate.disposeCount, 1);
  });
}
