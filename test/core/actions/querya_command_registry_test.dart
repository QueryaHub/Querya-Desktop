import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/actions/data_grid_command_bridge.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

void main() {
  final registry = QueryaCommandRegistry.instance;

  setUp(() {
    registry.resetForTest();
    SqlEditorCommandBridge.instance.resetForTest();
    DataGridCommandBridge.instance.resetForTest();
  });

  tearDown(() {
    registry.resetForTest();
    SqlEditorCommandBridge.instance.resetForTest();
    DataGridCommandBridge.instance.resetForTest();
  });

  test('register and search by title, id, and aliases', () {
    registry.register(
      QueryaCommand(
        id: 'test.foo',
        title: 'Foo Action',
        category: 'Tools',
        aliases: const ['bar', 'baz'],
        execute: (_) {},
      ),
    );

    expect(registry.search('foo action').map((c) => c.id), contains('test.foo'));
    expect(registry.search('bar').map((c) => c.id), contains('test.foo'));
    expect(registry.search('zzznomatch'), isEmpty);
  });

  test('unregister removes command', () {
    registry.register(
      QueryaCommand(id: 'x', title: 'X', execute: (_) {}),
    );
    registry.unregister('x');
    expect(registry['x'], isNull);
  });

  test('register does not let an extension overwrite a core id', () {
    registry.ensureCoreDefaults();
    final before = registry['querya.sql.execute']!;
    registry.register(
      QueryaCommand(
        id: 'querya.sql.execute',
        title: 'Stolen',
        sourceExtensionId: 'evil.driver',
        execute: (_) {},
      ),
    );
    expect(registry['querya.sql.execute']?.title, before.title);
    expect(registry['querya.sql.execute']?.sourceExtensionId, isNull);
  });

  test('core defaults: dark alias finds theme command', () {
    registry.ensureCoreDefaults();
    expect(
      registry.search('dark').map((c) => c.id),
      contains('querya.theme.toggle'),
    );
    expect(
      registry.search('settings').map((c) => c.id),
      contains('querya.app.preferences'),
    );
  });

  testWidgets('getAvailableCommands honors isEnabled', (tester) async {
    registry.register(
      QueryaCommand(
        id: 'test.always',
        title: 'Always',
        execute: (_) {},
      ),
    );
    registry.register(
      QueryaCommand(
        id: 'test.never',
        title: 'Never',
        isEnabled: (_) => false,
        execute: (_) {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final ids =
                registry.getAvailableCommands(context).map((c) => c.id);
            expect(ids, contains('test.always'));
            expect(ids, isNot(contains('test.never')));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('execute query is gated on SqlEditorCommandBridge',
      (tester) async {
    registry.ensureCoreDefaults();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              registry.getAvailableCommands(context).map((c) => c.id),
              isNot(contains('querya.sql.execute')),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    var ran = 0;
    SqlEditorCommandBridge.instance.register(
      connectionId: 1,
      onNew: () {},
      onOpen: () {},
      onSave: () {},
      onExecute: () => ran++,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              registry.getAvailableCommands(context).map((c) => c.id),
              contains('querya.sql.execute'),
            );
            registry['querya.sql.execute']!.execute(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(ran, 1);
  });

  testWidgets('go to object enabled under QueryaCommandHost', (tester) async {
    registry.ensureCoreDefaults();
    var opened = 0;
    await tester.pumpWidget(
      QueryaCommandHost(
        onShowQuickSwitcher: (_) => opened++,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                registry.getAvailableCommands(context).map((c) => c.id),
                contains('querya.goto.object'),
              );
              registry['querya.goto.object']!.execute(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(opened, 1);
  });

  test('core catalog includes workspace, SQL, grid, and app commands', () {
    registry.ensureCoreDefaults();
    const expected = [
      'querya.view.toggleSidebar',
      'querya.workspace.close',
      'querya.workspace.home',
      'querya.connection.new',
      'querya.connection.connect',
      'querya.connection.disconnect',
      'querya.connection.reconnect',
      'querya.connection.toggleReadOnly',
      'querya.sql.execute',
      'querya.sql.newTab',
      'querya.sql.closeTab',
      'querya.sql.format',
      'querya.sql.clear',
      'querya.grid.toggleFilter',
      'querya.grid.inspectCell',
      'querya.grid.copyCsv',
      'querya.grid.copyJson',
      'querya.grid.copyMarkdown',
      'querya.grid.saveExport',
      'querya.grid.applyStaged',
      'querya.app.preferences',
      'querya.app.extensions',
      'querya.app.updates',
      'querya.app.welcome',
      'querya.app.about',
    ];
    final ids = registry.commands.map((c) => c.id).toSet();
    expect(ids, containsAll(expected));
  });

  testWidgets('SQL format/clear/new/close hit SqlEditorCommandBridge',
      (tester) async {
    registry.ensureCoreDefaults();
    var format = 0;
    var clear = 0;
    var created = 0;
    var closed = 0;
    SqlEditorCommandBridge.instance.register(
      connectionId: 1,
      onNew: () => created++,
      onOpen: () {},
      onSave: () {},
      onCloseTab: () => closed++,
      onFormat: () => format++,
      onClear: () => clear++,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final ids =
                registry.getAvailableCommands(context).map((c) => c.id);
            expect(ids, contains('querya.sql.newTab'));
            expect(ids, contains('querya.sql.closeTab'));
            expect(ids, contains('querya.sql.format'));
            expect(ids, contains('querya.sql.clear'));
            registry['querya.sql.format']!.execute(context);
            registry['querya.sql.clear']!.execute(context);
            registry['querya.sql.newTab']!.execute(context);
            registry['querya.sql.closeTab']!.execute(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(format, 1);
    expect(clear, 1);
    expect(created, 1);
    expect(closed, 1);
  });

  testWidgets('grid commands hit DataGridCommandBridge', (tester) async {
    registry.ensureCoreDefaults();
    var filter = 0;
    var inspect = 0;
    DataExportFormat? copied;
    var exported = 0;
    var applied = 0;
    var dirty = true;
    DataGridCommandBridge.instance.register(
      onToggleFilter: () => filter++,
      onToggleInspector: () => inspect++,
      onCopy: (format) => copied = format,
      onSaveExport: () => exported++,
      onApplyStaged: () => applied++,
      canApplyStaged: () => dirty,
      hasRows: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final ids =
                registry.getAvailableCommands(context).map((c) => c.id);
            expect(ids, contains('querya.grid.toggleFilter'));
            expect(ids, contains('querya.grid.copyCsv'));
            expect(ids, contains('querya.grid.applyStaged'));
            registry['querya.grid.toggleFilter']!.execute(context);
            registry['querya.grid.inspectCell']!.execute(context);
            registry['querya.grid.copyCsv']!.execute(context);
            registry['querya.grid.saveExport']!.execute(context);
            registry['querya.grid.applyStaged']!.execute(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(filter, 1);
    expect(inspect, 1);
    expect(copied, DataExportFormat.csv);
    expect(exported, 1);
    expect(applied, 1);

    dirty = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              registry.getAvailableCommands(context).map((c) => c.id),
              isNot(contains('querya.grid.applyStaged')),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('connection and workspace commands hit QueryaCommandHost',
      (tester) async {
    registry.ensureCoreDefaults();
    var home = 0;
    var closed = 0;
    var connected = 0;
    var disconnected = 0;
    var reconnected = 0;
    var ro = 0;
    await tester.pumpWidget(
      QueryaCommandHost(
        onGoHome: () => home++,
        onCloseWorkspace: () => closed++,
        onConnect: () => connected++,
        onDisconnect: () => disconnected++,
        onReconnect: () => reconnected++,
        onToggleReadOnly: () => ro++,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              registry['querya.workspace.home']!.execute(context);
              registry['querya.workspace.close']!.execute(context);
              registry['querya.connection.connect']!.execute(context);
              registry['querya.connection.disconnect']!.execute(context);
              registry['querya.connection.reconnect']!.execute(context);
              registry['querya.connection.toggleReadOnly']!.execute(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(home, 1);
    expect(closed, 1);
    expect(connected, 1);
    expect(disconnected, 1);
    expect(reconnected, 1);
    expect(ro, 1);
  });

  testWidgets('toggle sidebar enabled under QueryaCommandHost', (tester) async {
    registry.ensureCoreDefaults();
    var toggled = 0;
    await tester.pumpWidget(
      QueryaCommandHost(
        onToggleSidebar: () => toggled++,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                registry.getAvailableCommands(context).map((c) => c.id),
                contains('querya.view.toggleSidebar'),
              );
              registry['querya.view.toggleSidebar']!.execute(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(toggled, 1);
  });
}
