import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_shortcuts_section.dart';
import 'package:querya_desktop/features/workspace/generic_sql_workspace.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show OutlineButton;

import '../../support/fake_sql_execution_delegate.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';


/// A hung test must fail in a minute instead of blocking CI for ten.
const _timeout = Timeout(Duration(seconds: 60));


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ConnectionRow connection;

  setUpAll(() async {
    tempDir = await initTestLocalDb('generic_ws_keys_');
    // History is written with a foreign key to `connections`, so the workspace
    // needs a connection that really exists.
    const row = ConnectionRow(
      type: 'sqlite',
      name: 'Synthetic',
      host: '/tmp/synthetic.db',
      createdAt: '2026-01-01T00:00:00Z',
    );
    final id = await LocalDb.instance.addConnection(row);
    connection = row.copyWith(id: id);
  });
  tearDownAll(() => disposeTestLocalDb(tempDir));

  tearDown(() {
    SqlEditorCommandBridge.instance.unregister(connectionId: connection.id);
  });

  Future<GenericSqlWorkspaceState> pumpWorkspace(
    WidgetTester tester,
    FakeSqlExecutionDelegate delegate, {
    String? initialSql,
  }) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: GenericSqlWorkspace(
            connectionRow: connection,
            delegate: delegate,
            dialect: SqlDialect.sqlite,
            initialSql: initialSql,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<GenericSqlWorkspaceState>(
      find.byType(GenericSqlWorkspace),
    );
  }

  /// Lets the real async work behind `execute` (SQLite settings reads) finish.
  /// The action itself runs in the test zone; each round gives real time to
  /// the pending I/O and then pumps so the continuation (a fake-async
  /// microtask) runs and can start the next step.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the Execute button runs the active tab and shows the result', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT n FROM t',
    );

    await tester.tap(find.widgetWithText(OutlineButton, 'Execute (F5)'));
    await settle(tester);

    expect(delegate.executed, ['SELECT n FROM t']);
    expect(state.activeSession.columns, ['n']);
    expect(state.activeSession.rows, [
      ['1'],
    ]);
    expect(state.activeSession.statusLine, startsWith('1 row(s).'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('F5 executes the active tab', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await settle(tester);

    expect(delegate.executed, ['SELECT 1']);
  });

  testWidgets('Ctrl+Enter executes the active tab', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    await pumpWorkspace(tester, delegate, initialSql: 'SELECT 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('Ctrl+T opens a tab and Ctrl+W closes it', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Query 2'), findsNothing);
    expect(state.activeSession.title, 'Query 1');
  });

  testWidgets('Ctrl+Tab and Ctrl+Shift+Tab cycle through the tabs', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    state.addNewTab();
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 1');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(state.activeSession.title, 'Query 2');
  });

  testWidgets('blank SQL is not sent to the database', timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate, initialSql: '   ');

    unawaited(state.execute());
    await settle(tester);

    expect(delegate.executed, isEmpty);
  });

  testWidgets('only the selected text runs when there is a selection', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1; SELECT 2');

    // The selection is made through the mounted editor, as a user does; setting
    // the controller value directly is what made the test hang before.
    final editor = tester.state<material.EditableTextState>(
      find.byType(material.EditableText).first,
    );
    editor.userUpdateTextEditingValue(
      const TextEditingValue(
        text: 'SELECT 1; SELECT 2',
        selection: TextSelection(baseOffset: 10, extentOffset: 18),
      ),
      null,
    );
    await tester.pump();
    expect(state.activeSession.controller.selection.textInside(
        state.activeSession.controller.text), 'SELECT 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('a second execute is ignored while a query is running', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate()..gate = Completer<void>();
    final state = await pumpWorkspace(tester, delegate, initialSql: 'SELECT 1');

    unawaited(state.execute());
    await settle(tester);
    expect(state.activeSession.running, isTrue);

    unawaited(state.execute());
    await tester.pump();
    expect(delegate.executed, ['SELECT 1']);

    delegate.gate!.complete();
    await settle(tester);
    expect(state.activeSession.running, isFalse);
    expect(delegate.executed, ['SELECT 1']);
  });

  testWidgets('a failing query shows its error and clears the running state', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => throw Exception('syntax error near FORM'),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT * FORM t',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(state.activeSession.error, contains('syntax error near FORM'));
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('a statement that returns no rows reports the affected count', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => const SqlExecutionResult(affectedRows: 3),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'UPDATE t SET a = 1 WHERE b = 2',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(state.activeSession.statusLine, 'OK. Rows affected: 3.');
    expect(state.activeSession.affectedRows, 3);
  });

  testWidgets('the format command upper-cases SQL keywords', timeout: _timeout, (tester) async {
    await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'select id from users',
    );

    SqlEditorCommandBridge.instance.invokeFormat();
    await tester.pumpAndSettle();

    final state = tester.state<GenericSqlWorkspaceState>(
      find.byType(GenericSqlWorkspace),
    );
    expect(state.activeSession.controller.text, 'SELECT id FROM users');
  });

  testWidgets('the clear command empties the editor', timeout: _timeout, (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'SELECT 1',
    );

    SqlEditorCommandBridge.instance.invokeClear();
    await tester.pumpAndSettle();

    expect(state.activeSession.controller.text, isEmpty);
  });

  testWidgets('Ctrl+Enter runs only the statement under the caret', timeout: _timeout,
      (tester) async {
    final delegate = FakeSqlExecutionDelegate();
    final state = await pumpWorkspace(tester, delegate,
        initialSql: 'SELECT 1; SELECT 2; SELECT 3');
    // The caret sits inside "SELECT 2".
    state.activeSession.controller.selection =
        const TextSelection.collapsed(offset: 12);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(delegate.executed, ['SELECT 2']);
  });

  testWidgets('a script stops at the first error and points at its statement',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (sql) {
        if (sql == 'SELECT broken') throw Exception('no such column: broken');
        return const SqlExecutionResult(affectedRows: 1);
      },
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'SELECT 1;\nSELECT 2;\nSELECT broken;\nSELECT 4;\nSELECT 5',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(delegate.executed, ['SELECT 1', 'SELECT 2', 'SELECT broken']);
    expect(
      state.activeSession.error,
      'Statement 3 of 5 failed (line 3): Exception: no such column: broken',
    );
    expect(state.activeSession.controller.selection.baseOffset, 20);
    expect(state.activeSession.running, isFalse);
  });

  testWidgets('a script that succeeds reports its statements and rows',
      timeout: _timeout, (tester) async {
    final delegate = FakeSqlExecutionDelegate(
      onExecute: (_) => const SqlExecutionResult(affectedRows: 2),
    );
    final state = await pumpWorkspace(
      tester,
      delegate,
      initialSql: 'INSERT INTO t VALUES (1);\nINSERT INTO t VALUES (2);\nINSERT INTO t VALUES (3)',
    );

    unawaited(state.execute());
    await settle(tester);

    expect(delegate.executed, hasLength(3));
    expect(state.activeSession.statusLine, '3 statements · 6 rows affected');
    expect(state.activeSession.affectedRows, 6);
  });

  testWidgets('the toolbar stays on one row on a narrow window', timeout: _timeout,
      (tester) async {
    await pumpWorkspace(tester, FakeSqlExecutionDelegate());
    await tester.binding.setSurfaceSize(const material.Size(800, 700));
    await tester.pumpAndSettle();

    final run = find.byKey(const material.ValueKey('run_script'));
    final session = find.byKey(const material.ValueKey('session_menu'));
    expect(run, findsOneWidget);
    expect(session, findsOneWidget);
    expect(tester.getCenter(session).dy, closeTo(tester.getCenter(run).dy, 1));
  });

  testWidgets('no Query caption and no Data Output bar above the results',
      timeout: _timeout, (tester) async {
    await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    expect(find.text('Query'), findsNothing);
    expect(find.text('Data Output'), findsNothing);
    expect(find.byKey(const material.ValueKey('open_diagram_tab')), findsOneWidget);
  });

  testWidgets('a double click on a diagram card opens the table browser',
      timeout: _timeout, (tester) async {
    final opened = <QueryaSchemaObject>[];
    final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: [
          ['users', 'id', 'INTEGER', '1'],
        ]);
      }
      return const SqlExecutionResult();
    });
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaCommandHost(
          onOpenSchemaObject: opened.add,
          child: material.SizedBox.expand(
            child: GenericSqlWorkspace(
              connectionRow: connection,
              delegate: delegate,
              dialect: SqlDialect.sqlite,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const material.ValueKey('open_diagram_tab')));
    await settle(tester);
    final card = find.byKey(const material.ValueKey('erd_table_users'));
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await settle(tester);

    expect(opened, hasLength(1));
    expect(opened.single.name, 'users');
    expect(opened.single.kind, QueryaSchemaObjectKind.table);
    // No SQL tab: the browser opens instead.
    expect(delegate.executed.where((q) => q.startsWith('SELECT * FROM')),
        isEmpty);
  });

  Future<FakeSqlExecutionDelegate> pumpDiagram(
    WidgetTester tester,
    SqlDialect dialect,
    String table, {
    void Function(QueryaSchemaObject)? onOpen,
  }) async {
    final delegate = FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(dialect)) {
        return SqlExecutionResult(rows: [
          [table, 'id', 'integer', '1'],
        ]);
      }
      return const SqlExecutionResult();
    });
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaCommandHost(
          onOpenSchemaObject: onOpen ?? (_) {},
          child: material.SizedBox.expand(
            child: GenericSqlWorkspace(
              connectionRow: connection,
              delegate: delegate,
              dialect: dialect,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const material.ValueKey('open_diagram_tab')));
    await settle(tester);
    return delegate;
  }

  testWidgets('a double click opens a table of another schema in the browser (#1155)',
      timeout: _timeout, (tester) async {
    final opened = <QueryaSchemaObject>[];
    await pumpDiagram(tester, SqlDialect.postgres, 'sales.orders',
        onOpen: opened.add);
    final card = find.byKey(const material.ValueKey('erd_table_sales.orders'));
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await settle(tester);

    expect(opened, hasLength(1));
    expect(opened.single.schema, 'sales');
    expect(opened.single.name, 'orders');
    expect(opened.single.kind, QueryaSchemaObjectKind.table);
  });

  for (final (dialect, table, quoted) in [
    (SqlDialect.postgres, 'sales.orders', '"sales"."orders"'),
    // A dot in a MySQL name is part of the name.
    (SqlDialect.mysql, 'order.items', '`order.items`'),
  ]) {
    testWidgets(
        '${dialect.name}: Open in SQL quotes $table for the dialect (#1155)',
        timeout: _timeout,
        variant: TargetPlatformVariant.only(material.TargetPlatform.linux),
        (tester) async {
      final delegate = await pumpDiagram(tester, dialect, table);
      final card = find.byKey(material.ValueKey('erd_table_$table'));
      await tester.tap(card, buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(material.ValueKey('erd_menu_sql_$table')));
      await settle(tester);

      expect(
        delegate.executed.where((q) => q.contains('SELECT * FROM $quoted')),
        isNotEmpty,
        reason: 'executed: ${delegate.executed}',
      );
    });
  }

  testWidgets('the Diagram reads the catalog through its own delegate, not the editor',
      timeout: _timeout, (tester) async {
    final editor = FakeSqlExecutionDelegate();
    final catalog = FakeSqlExecutionDelegate(onExecute: (sql) {
      if (sql == ErdCatalog.columnsSql(SqlDialect.sqlite)) {
        return const SqlExecutionResult(rows: [
          ['users', 'id', 'INTEGER', '1'],
        ]);
      }
      return const SqlExecutionResult();
    });
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox.expand(
          child: GenericSqlWorkspace(
            connectionRow: connection,
            delegate: editor,
            dialect: SqlDialect.sqlite,
            catalogDelegateFactory: () => catalog,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const material.ValueKey('open_diagram_tab')));
    await settle(tester);

    expect(find.byKey(const material.ValueKey('erd_table_users')), findsOneWidget);
    expect(catalog.executed, contains(ErdCatalog.columnsSql(SqlDialect.sqlite)));
    expect(editor.executed, isEmpty,
        reason: 'the editor session must not carry the catalog reads');
  });

  testWidgets('Shift+Alt+F formats the active tab', timeout: _timeout,
      (tester) async {
    final state = await pumpWorkspace(
      tester,
      FakeSqlExecutionDelegate(),
      initialSql: 'select n from t',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(state.activeSession.controller.text, 'SELECT n FROM t');
  });

  testWidgets(
      'every SQL Editor key in the shortcuts reference is bound in the '
      'workspace (#1148)', timeout: _timeout, (tester) async {
    await pumpWorkspace(tester, FakeSqlExecutionDelegate());

    final bound = <material.SingleActivator>[
      for (final w in tester.widgetList<material.CallbackShortcuts>(
        find.descendant(
          of: find.byType(GenericSqlWorkspace),
          matching: find.byType(material.CallbackShortcuts),
        ),
      ))
        ...w.bindings.keys.whereType<material.SingleActivator>(),
    ];

    final missing = <String>[];
    for (final item in PreferencesShortcutsSection.allShortcuts
        .where((s) => s.category == 'SQL Editor')) {
      for (final combo in item.allKeys) {
        final want = _activatorFor(combo);
        final found = bound.any((b) =>
            b.trigger == want.trigger &&
            b.control == want.control &&
            b.shift == want.shift &&
            b.alt == want.alt &&
            b.meta == want.meta);
        if (!found) missing.add('${item.action}: ${combo.join('+')}');
      }
    }
    expect(missing, isEmpty);
  });
}

/// The activator a reference row describes, e.g. `['Ctrl', 'Shift', 'Enter']`.
material.SingleActivator _activatorFor(List<String> keys) {
  var control = false, shift = false, alt = false, meta = false;
  LogicalKeyboardKey? trigger;
  for (final k in keys) {
    switch (k) {
      case 'Ctrl':
        control = true;
      case '⌘':
        meta = true;
      case 'Shift':
        shift = true;
      case 'Alt':
        alt = true;
      case 'Enter':
        trigger = LogicalKeyboardKey.enter;
      case 'Tab':
        trigger = LogicalKeyboardKey.tab;
      case 'F5':
        trigger = LogicalKeyboardKey.f5;
      default:
        expect(k.length, 1, reason: 'unknown key label "$k"');
        trigger = LogicalKeyboardKey.findKeyByKeyId(
            k.toLowerCase().codeUnitAt(0));
    }
  }
  expect(trigger, isNotNull, reason: 'no key in ${keys.join('+')}');
  return material.SingleActivator(
    trigger!,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}
