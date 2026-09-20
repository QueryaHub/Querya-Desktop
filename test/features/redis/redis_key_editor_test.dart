import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/redis/redis_key_editor.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpEditor(
    WidgetTester tester, {
    required RedisConnectionTestFake fake,
    required bool isReadOnly,
    material.VoidCallback? onKeyDeleted,
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
}
