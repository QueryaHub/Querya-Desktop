import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';

void main() {
  final registry = QueryaCommandRegistry.instance;

  setUp(() {
    registry.resetForTest();
    SqlEditorCommandBridge.instance.resetForTest();
  });

  tearDown(() {
    registry.resetForTest();
    SqlEditorCommandBridge.instance.resetForTest();
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
