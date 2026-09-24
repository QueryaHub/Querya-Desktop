import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/redis/redis_key_editor.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpEditor(
    WidgetTester tester, {
    required RedisConnectionTestFake fake,
    required bool isReadOnly,
    material.VoidCallback? onKeyDeleted,
    material.ValueChanged<RedisBulkValue>? onKeyRenamed,
    material.Size size = const material.Size(800, 600),
    String keyType = 'string',
    String keyName = 'session:1',
  }) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: size.width,
            height: size.height,
            child: RedisKeyEditor(
              connection: fake,
              database: 0,
              keyName: keyName,
              keyType: keyType,
              isReadOnly: isReadOnly,
              onKeyDeleted: onKeyDeleted,
              onKeyRenamed: onKeyRenamed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('RedisKeyEditor hides Save, TTL, and delete when locked',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: true);

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Set TTL'), findsNothing);
    expect(find.byTooltip('Delete key'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor shows Save when the session is writable',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: false);

    expect(find.text('Save'), findsOneWidget);
    expect(find.byTooltip('Set TTL'), findsOneWidget);
    expect(find.byTooltip('Delete key'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor Delete Cancel does not call onKeyDeleted',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(800, 700));
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();
    var deleted = false;

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      onKeyDeleted: () => deleted = true,
      size: const material.Size(800, 700),
    );

    await tester.tap(find.byTooltip('Delete key'));
    await tester.pumpAndSettle();

    expect(find.text('DEL session:1'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);
    expect(find.byTooltip('Delete key'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor list loads a page instead of LRANGE 0 -1',
      (tester) async {
    final fake = RedisConnectionTestFake(
      listItems: List.generate(250, (i) => 'item_$i'),
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: true,
      keyType: 'list',
      keyName: 'jobs',
      size: const material.Size(800, 700),
    );

    expect(find.text('List items (200 / 250)'), findsOneWidget);
    expect(find.text('Load more (200 / 250)'), findsOneWidget);
    expect(find.text('item_0'), findsOneWidget);
    expect(find.text('item_249'), findsNothing);

    await tester.tap(find.text('Load more (200 / 250)'));
    await tester.pumpAndSettle();

    expect(find.text('List items (250 / 250)'), findsOneWidget);
    expect(find.text('Load more (200 / 250)'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor hash uses HSCAN and warns when huge',
      (tester) async {
    final fake = RedisConnectionTestFake(
      hashFirstPage: const {'email': 'a@b.c'},
      hashSecondPage: const {'name': 'Ada'},
      hlenResult: 15000,
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: true,
      keyType: 'hash',
      keyName: 'user:1',
      size: const material.Size(800, 700),
    );

    expect(
      find.textContaining('Large key (15000 members)'),
      findsOneWidget,
    );
    expect(find.text('Hash fields (1 / 15000)'), findsOneWidget);
    expect(find.text('email'), findsOneWidget);
    expect(find.text('name'), findsNothing);

    await tester.tap(find.text('Load more (1 / 15000)'));
    await tester.pumpAndSettle();
    expect(find.text('name'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor stream does not GET or show Save',
      (tester) async {
    final fake = RedisConnectionTestFake(
      getResult: 'should-not-load',
      typeResult: 'stream',
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'stream',
      keyName: 'querya:stream:events',
    );

    expect(find.text('Unsupported type'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('should-not-load'), findsNothing);
    expect(fake.sentCommands.contains('GET'), isFalse);
    expect(fake.sentCommands.contains('SET'), isFalse);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor unknown does not GET until TYPE succeeds',
      (tester) async {
    final fake = RedisConnectionTestFake(
      getResult: 'should-not-load',
      failType: true,
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'unknown',
      keyName: 'maybe-module',
    );

    expect(find.text('Type unknown'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('should-not-load'), findsNothing);
    expect(fake.sentCommands.contains('GET'), isFalse);
    expect(fake.sentCommands.contains('SET'), isFalse);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor unknown TYPE stream does not GET',
      (tester) async {
    final fake = RedisConnectionTestFake(
      getResult: 'should-not-load',
      typeResult: 'stream',
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'unknown',
      keyName: 'querya:stream:events',
    );

    expect(find.text('Unsupported type'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.textContaining('STREAM'), findsWidgets);
    expect(fake.sentCommands.contains('TYPE'), isTrue);
    expect(fake.sentCommands.contains('GET'), isFalse);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor unknown TYPE string then GET and Save',
      (tester) async {
    final fake =
        RedisConnectionTestFake(getResult: 'hello', typeResult: 'string');
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'unknown',
      keyName: 'session:1',
    );

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(fake.sentCommands.contains('TYPE'), isTrue);
    expect(fake.sentCommands.contains('GET'), isTrue);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor binary GET shows hex and hides Save',
      (tester) async {
    final fake = RedisConnectionTestFake(
      getBytesResult: const [0xff, 0xfe, 0x01],
    );
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: false);

    expect(find.textContaining('Binary value'), findsOneWidget);
    expect(find.text('fffe01'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('[255, 254, 1]'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor hides Rename key when read-only', (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: true);

    expect(find.byTooltip('Rename key'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor renames key when target does not exist',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();
    RedisBulkValue? renamedKey;

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      onKeyRenamed: (k) => renamedKey = k,
    );

    expect(find.byTooltip('Rename key'), findsOneWidget);
    await tester.tap(find.byTooltip('Rename key'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Key'), findsOneWidget);
    // Enter new key name
    final textField = find.byType(shadcn.TextField);
    await tester.enterText(textField, 'session:renamed');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('session:renamed'), findsOneWidget);
    expect(renamedKey?.label, 'session:renamed');
    expect(fake.sentCommands.contains('EXISTS'), isTrue);
    expect(fake.sentCommands.contains('RENAME'), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeyEditor prompts overwrite confirmation when target key exists',
      (tester) async {
    final fake = RedisConnectionTestFake(
      getResult: 'hello',
      firstScanKeys: const ['session:exists'],
    );
    await fake.connect();
    RedisBulkValue? renamedKey;

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      onKeyRenamed: (k) => renamedKey = k,
    );

    await tester.tap(find.byTooltip('Rename key'));
    await tester.pumpAndSettle();

    final textField = find.byType(shadcn.TextField);
    await tester.enterText(textField, 'session:exists');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // Destructive confirmation dialog should appear
    expect(find.text('RENAME session:1 session:exists'), findsOneWidget);

    // Cancel first
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(renamedKey, isNull);
    expect(find.text('session:1'), findsOneWidget);

    // Now try again and confirm
    await tester.tap(find.byTooltip('Rename key'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(shadcn.TextField), 'session:exists');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('RENAME session:1 session:exists'), findsOneWidget);
    // Destructive dialog requires acknowledging checkbox for high risk
    await tester.tap(find.byType(material.Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Execute Destructive Statement'));
    await tester.pumpAndSettle();

    expect(renamedKey?.label, 'session:exists');
    expect(find.text('session:exists'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor list item hides edit and delete when read-only',
      (tester) async {
    final fake = RedisConnectionTestFake(
      listItems: ['task1'],
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: true,
      keyType: 'list',
      keyName: 'jobs',
    );

    expect(find.text('task1'), findsOneWidget);
    expect(find.byTooltip('Edit item'), findsNothing);
    expect(find.byTooltip('Delete item'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor list item edits element via LSET',
      (tester) async {
    final fake = RedisConnectionTestFake(
      listItems: ['task1'],
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'list',
      keyName: 'jobs',
    );

    expect(find.text('task1'), findsOneWidget);
    expect(find.byTooltip('Edit item'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit item'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Item [0]'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(shadcn.AlertDialog),
      matching: find.byType(shadcn.TextField),
    );
    await tester.enterText(field, 'task1_updated');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.sentCommands.contains('LSET'), isTrue);
    expect(fake.listItems, ['task1_updated']);
    expect(find.text('task1_updated'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeyEditor list item deletes element with confirmation',
      (tester) async {
    final fake = RedisConnectionTestFake(
      listItems: ['task1'],
    );
    await fake.connect();

    await pumpEditor(
      tester,
      fake: fake,
      isReadOnly: false,
      keyType: 'list',
      keyName: 'jobs',
    );

    expect(find.text('task1'), findsOneWidget);
    expect(find.byTooltip('Delete item'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();

    expect(find.text('LREM jobs 1 task1'), findsOneWidget);

    // Cancel first
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.listItems, ['task1']);
    expect(find.text('task1'), findsOneWidget);

    // Now confirm delete
    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(material.Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Execute Destructive Statement'));
    await tester.pumpAndSettle();

    expect(fake.sentCommands.contains('LREM'), isTrue);
    expect(fake.listItems.isEmpty, isTrue);
    expect(find.text('No items'), findsOneWidget);
    await fake.disconnect();
  });
  testWidgets(
      'RedisKeyEditor Refresh proceeds without dialog when string is unedited',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'original');
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: false);
    // One GET on initial load
    expect(fake.sentCommands.where((c) => c == 'GET').length, 1);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    // No discard dialog, GET called again
    expect(find.text('Unsaved changes'), findsNothing);
    expect(fake.sentCommands.where((c) => c == 'GET').length, 2);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeyEditor Refresh shows discard dialog when string is dirty',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'original');
    await fake.connect();

    await pumpEditor(tester, fake: fake, isReadOnly: false);
    expect(fake.sentCommands.where((c) => c == 'GET').length, 1);

    // Edit the string value
    final textField = find.byType(material.TextField).first;
    await tester.tap(textField);
    await tester.enterText(textField, 'edited');
    await tester.pump();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    // Discard dialog should appear
    expect(find.text('Unsaved changes'), findsOneWidget);

    // Cancel — no reload
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.sentCommands.where((c) => c == 'GET').length, 1);

    // Try refresh again and confirm discard
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(fake.sentCommands.where((c) => c == 'GET').length, 2);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeyEditorController.canNavigateAway returns true when string is clean',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();
    final controller = RedisKeyEditorController();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: RedisKeyEditor(
              connection: fake,
              database: 0,
              keyName: 'session:1',
              keyType: 'string',
              isReadOnly: false,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canLeave = await controller.canNavigateAway();
    expect(canLeave, isTrue);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeyEditorController.canNavigateAway shows dialog when string is dirty',
      (tester) async {
    final fake = RedisConnectionTestFake(getResult: 'hello');
    await fake.connect();
    final controller = RedisKeyEditorController();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: RedisKeyEditor(
              connection: fake,
              database: 0,
              keyName: 'session:1',
              keyType: 'string',
              isReadOnly: false,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dirty the field
    final textField = find.byType(material.TextField).first;
    await tester.tap(textField);
    await tester.enterText(textField, 'dirty value');
    await tester.pump();

    // Trigger navigation guard — dialog should appear
    bool? result;
    final future = controller.canNavigateAway().then((v) => result = v);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);

    // Dismiss with Cancel — guard returns false
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await future;
    expect(result, isFalse);

    // Trigger again — dismiss with Discard — guard returns true
    bool? result2;
    final future2 = controller.canNavigateAway().then((v) => result2 = v);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await future2;
    expect(result2, isTrue);
    await fake.disconnect();
  });
}
