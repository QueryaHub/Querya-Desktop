
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

/// #1275: the diagram keeps what the user arranged.
class _MemoryStore implements ErdLayoutStore {
  final layouts = <ErdLayoutKey, ErdSavedLayout>{};
  var writes = 0;

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async => layouts[key];

  @override
  Future<void> write(ErdLayoutKey key, ErdSavedLayout layout) async {
    writes++;
    layouts[key] = layout;
  }
}

const _key = ErdLayoutKey(connectionId: 1, scope: 'shop');

FakeSqlExecutionDelegate _catalog({bool withPayments = false}) =>
    FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return SqlExecutionResult(rows: [
          const ['users', 'id', 'INTEGER', '1'],
          const ['orders', 'user_id', 'INTEGER', '0'],
          if (withPayments) const ['payments', 'order_id', 'INTEGER', '0'],
        ]);
      }
      return const SqlExecutionResult(rows: [
        ['orders', 'user_id', 'users', 'id'],
      ]);
    });

Finder _card(String table) =>
    find.byKey(material.ValueKey('erd_table_$table'));

void main() {
  Future<void> pumpDiagram(
    WidgetTester t,
    _MemoryStore store, {
    bool withPayments = false,
    int? depth,
  }) async {
    await t.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: ErdView(
        key: material.UniqueKey(),
        source: SqlErdSource(
            delegate: _catalog(withPayments: withPayments),
            dialect: SqlDialect.sqlite),
        focusTable: depth == null ? null : 'orders',
        neighbourhoodDepth: depth,
        layoutStore: store,
        layoutKey: _key,
      ),
    ));
    await t.pump();
    await t.pump();
    await t.pump();
  }

  /// Unmounts the diagram (the tab closes) and lets the save run.
  Future<void> close(WidgetTester t) async {
    await t.pump(const Duration(seconds: 1));
    await t.pumpWidget(const material.SizedBox());
    await t.pump();
  }

  testWidgets('a dragged card is where it was left after a reopen', (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    final before = t.getTopLeft(_card('orders'));
    await t.drag(_card('orders'), const material.Offset(120, 60));
    await t.pump();
    final moved = t.getTopLeft(_card('orders'));
    expect(moved.dx - before.dx, greaterThan(100));
    await close(t);
    expect(store.layouts[_key], isNotNull);

    await pumpDiagram(t, store);
    expect(t.getTopLeft(_card('orders')), moved);
    await close(t);
  });

  testWidgets('a pending save is written when the tab closes at once',
      (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await t.drag(_card('orders'), const material.Offset(80, 0));
    await t.pump();
    // Closed before the save's pause ran out.
    await t.pumpWidget(const material.SizedBox());
    await t.pump();
    expect(store.layouts[_key]?.positions['orders'], isNotNull);
  });

  testWidgets('collapsed, hidden and keys only come back', (t) async {
    final store = _MemoryStore()
      ..layouts[_key] = const ErdSavedLayout(
        hidden: {'users'},
        detail: ErdDetail.keys,
      );
    await pumpDiagram(t, store);
    expect(_card('users'), findsNothing);
    expect(_card('orders'), findsOneWidget);
    await close(t);
  });

  testWidgets('a table new in the database is placed right of the arranged ones',
      (t) async {
    final store = _MemoryStore()
      ..layouts[_key] = const ErdSavedLayout(positions: {
        'users': Offset(40, 40),
        'orders': Offset(400, 300),
      });
    await pumpDiagram(t, store, withPayments: true);
    final orders = t.getRect(_card('orders'));
    final payments = t.getRect(_card('payments'));
    expect(payments.left, greaterThan(orders.right),
        reason: 'the new table does not land on an arranged one');
    await close(t);
  });

  testWidgets('a table gone from the database is dropped from the layout',
      (t) async {
    final store = _MemoryStore()
      ..layouts[_key] = const ErdSavedLayout(
        positions: {'users': Offset(40, 40), 'gone': Offset(600, 40)},
        hidden: {'gone'},
      );
    await pumpDiagram(t, store);
    await t.drag(_card('users'), const material.Offset(30, 0));
    await close(t);
    final saved = store.layouts[_key]!;
    expect(saved.positions.containsKey('gone'), isFalse);
    expect(saved.hidden, isNot(contains('gone')));
  });

  testWidgets('keys only keeps the cards where they are',
      (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await t.drag(_card('users'), const material.Offset(200, 120));
    await t.pump();
    final users = t.getTopLeft(_card('users'));
    await t.tap(find.byKey(const material.ValueKey('querya_tab_Keys')));
    await t.pump();
    expect(t.getTopLeft(_card('users')), users);
    await close(t);
  });

  testWidgets('a neighbourhood view is not kept', (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store, depth: 1);
    await t.drag(_card('orders'), const material.Offset(80, 40));
    await close(t);
    expect(store.writes, 0);
  });
}
