import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1282: groups made on the diagram, dragged by their title, kept.
class _MemoryStore implements ErdLayoutStore {
  _MemoryStore([this.initial]);

  final ErdSavedLayout? initial;
  final layouts = <ErdLayoutKey, ErdSavedLayout>{};

  @override
  Future<ErdSavedLayout?> read(ErdLayoutKey key) async =>
      layouts[key] ?? initial;

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

final _frame = find.byKey(const material.ValueKey('erd_group_g1'));

void main() {
  final desktop = TargetPlatformVariant.only(material.TargetPlatform.linux);

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

  /// Shift + click: the card waits out its double tap before it counts.
  Future<void> mark(WidgetTester t, String table) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(_card(table));
    await t.pump(const Duration(milliseconds: 400));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }

  testWidgets('marked tables become a group that moves and is kept',
      variant: desktop, (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await mark(t, 'users');
    await mark(t, 'orders');
    final button = find.byKey(const material.ValueKey('erd_group_marked'));
    expect(find.descendant(of: button, matching: find.text('Group 2 tables')),
        findsOneWidget);

    await t.tap(button);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const material.ValueKey('erd_group_submit')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(_frame, findsOneWidget);
    expect(find.text('Group 1'), findsOneWidget);
    expect(button, findsNothing);

    // Dragging the title moves both tables, not the others.
    final users = t.getTopLeft(_card('users'));
    final orders = t.getTopLeft(_card('orders'));
    final tags = t.getTopLeft(_card('tags'));
    await t.drag(_frame, const material.Offset(90, 40));
    await t.pump();
    await t.pump();
    final moved = t.getTopLeft(_card('users')) - users;
    expect(moved.dx, greaterThan(40));
    final movedOrders = t.getTopLeft(_card('orders')) - orders;
    expect(movedOrders.dx, closeTo(moved.dx, 0.01));
    expect(movedOrders.dy, closeTo(moved.dy, 0.01));
    expect(t.getTopLeft(_card('tags')), tags);

    // Kept with the layout.
    await t.pump(const Duration(seconds: 1));
    final saved = store.layouts[_key]!.groups.single;
    expect(saved.name, 'Group 1');
    expect(saved.tables, ['users', 'orders']);

    // A reopen draws it again.
    await pumpDiagram(t, store);
    expect(_frame, findsOneWidget);

    await t.tap(_frame, buttons: kSecondaryButton);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const material.ValueKey('erd_group_ungroup_g1')));
    await t.pump(const Duration(milliseconds: 300));
    expect(_frame, findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(store.layouts[_key]!.groups, isEmpty);
  });

  testWidgets('Esc clears the marks, a plain click picks one table',
      variant: desktop, (t) async {
    await pumpDiagram(t, _MemoryStore());
    final button = find.byKey(const material.ValueKey('erd_group_marked'));
    await mark(t, 'users');
    expect(button, findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(button, findsNothing);

    await mark(t, 'users');
    await t.tap(_card('tags'));
    await t.pump(const Duration(milliseconds: 400));
    expect(button, findsNothing);
  });

  testWidgets('a card menu groups the table and takes it out again',
      variant: desktop, (t) async {
    final store = _MemoryStore();
    await pumpDiagram(t, store);
    await t.tap(_card('tags'), buttons: kSecondaryButton);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('New group…'), findsOneWidget);
    await t.tap(find.byKey(const material.ValueKey('erd_menu_group_tags')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(
        find.byKey(const material.ValueKey('erd_group_name')), 'Lookup');
    await t.enterText(
        find.byKey(const material.ValueKey('erd_group_note')), 'Static data');
    await t.tap(find.byKey(const material.ValueKey('erd_group_submit')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Lookup'), findsOneWidget);
    expect(find.byKey(const material.ValueKey('erd_group_note_g1')),
        findsOneWidget);

    await t.tap(_card('tags'), buttons: kSecondaryButton);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const material.ValueKey('erd_menu_ungroup_tags')));
    await t.pump(const Duration(milliseconds: 300));
    expect(_frame, findsNothing);
  });

  testWidgets('a group over other cards gathers its own tables, others stay',
      variant: desktop, (t) async {
    // users, orders and tags in a row: a frame around users and tags would
    // cover orders.
    final store = _MemoryStore(const ErdSavedLayout(positions: {
      'users': Offset(40, 60),
      'orders': Offset(300, 60),
      'tags': Offset(560, 60),
    }));
    await pumpDiagram(t, store);
    final orders = t.getRect(_card('orders'));

    await mark(t, 'users');
    await mark(t, 'tags');
    await t.tap(find.byKey(const material.ValueKey('erd_group_marked')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const material.ValueKey('erd_group_submit')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(t.getRect(_card('orders')), orders);
    final together =
        t.getRect(_card('users')).expandToInclude(t.getRect(_card('tags')));
    expect(together.overlaps(orders), isFalse);
    expect(find.textContaining('together'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });
}
