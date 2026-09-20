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
              keyName: 'session:1',
              keyType: 'string',
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
}
