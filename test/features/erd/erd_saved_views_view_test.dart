import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1284: views are created, switched, renamed, deleted and kept.
class _MemoryStore implements ErdLayoutStore {
  final layouts = <ErdLayoutKey, ErdSavedLayout>{};

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async => layouts[key];

  @override
  Future<void> write(ErdLayoutKey key, ErdSavedLayout layout) async =>
      layouts[key] = layout;
}

const _key = ErdLayoutKey(connectionId: 1, scope: 'shop');

FakeSqlExecutionDelegate _catalog() =>
    FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: [
          ['users', 'id', 'INTEGER', '1'],
          ['orders', 'user_id', 'INTEGER', '0'],
          ['tags', 'id', 'INTEGER', '1'],
        ]);
      }
      return const SqlExecutionResult(rows: [
        ['orders', 'user_id', 'users', 'id'],
      ]);
    });

Finder _card(String table) =>
    find.byKey(material.ValueKey('erd_table_$table'));

void main() {
  Future<void> pumpDiagram(WidgetTester t, _MemoryStore store) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: ErdView(
        key: material.UniqueKey(),
        source: SqlErdSource(delegate: _catalog(), dialect: SqlDialect.sqlite),
        layoutStore: store,
        layoutKey: _key,
      ),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> openMenu(WidgetTester t) async {
    await t.tap(find.byKey(const material.ValueKey('erd_views')));
    await settle(t);
  }

  Future<void> choose(WidgetTester t, String label) async {
    await openMenu(t);
    await t.tap(find.text(label).last);
    await settle(t);
  }

  Future<void> named(WidgetTester t, String name) async {
    await t.enterText(find.byKey(const material.ValueKey('erd_view_name')), name);
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('erd_view_submit')));
    await settle(t);
  }

  testWidgets('a view restores its tables, positions and survives a reopen',
      (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);

    // Hide "tags" by hand, then keep that as a view.
    await t.tap(_card('tags'), buttons: 2);
    await settle(t);
    await t.tap(find.text('Hide from diagram'));
    await settle(t);
    expect(_card('tags'), findsNothing);
    await choose(t, 'Save as new view…');
    await named(t, 'Core');
    expect(find.text('Core'), findsOneWidget);

    // Back to all tables: "tags" is there again.
    await choose(t, 'All tables');
    expect(_card('tags'), findsOneWidget);

    // And the view hides it again.
    await openMenu(t);
    await t.tap(find.textContaining('Core (2)'));
    await settle(t);
    expect(_card('tags'), findsNothing);
    expect(_card('users'), findsOneWidget);

    await t.pump(const Duration(seconds: 1));
    final saved = store.layouts[_key]!;
    expect(saved.activeView, 'v1');
    expect(saved.views.single.tables, {'users', 'orders'});
    // The diagram's own state kept "tags" shown.
    expect(saved.hidden, isEmpty);

    // Reopened in the view it was left in.
    await pumpDiagram(t, store);
    expect(_card('tags'), findsNothing);
    expect(find.text('Core'), findsOneWidget);
  });

  testWidgets('a view is renamed and deleted', (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await choose(t, 'Save as new view…');
    await named(t, 'First');
    await choose(t, 'Rename view…');
    await named(t, 'Second');
    expect(find.text('Second'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(store.layouts[_key]!.views.single.name, 'Second');

    await choose(t, 'Delete view');
    expect(find.text('All tables'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(store.layouts[_key]!.views, isEmpty);
    expect(store.layouts[_key]!.activeView, isNull);
  });
}
