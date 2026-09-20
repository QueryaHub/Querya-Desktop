import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/redis/redis_keys_view.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RedisKeysView lists keys from ListView after load',
      (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const ['key_a', 'key_b'],
      dbSizeResult: 2,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: RedisKeysView(
              connection: fake,
              database: 0,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(find.byType(material.ListView), findsWidgets);
    expect(find.text('key_a'), findsOneWidget);
    expect(find.text('key_b'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeysView shows empty state when scan returns no keys',
      (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const [],
      dbSizeResult: 0,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 400,
          child: RedisKeysView(
            connection: fake,
            database: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('No keys found'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeysView hides delete and shows Read-only session when locked',
      (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const ['key_a'],
      dbSizeResult: 1,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: RedisKeysView(
              connection: fake,
              database: 0,
              isReadOnly: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('key_a'), findsOneWidget);
    expect(find.text('Read-only session'), findsOneWidget);
    expect(find.byTooltip('Delete key'), findsNothing);
    await fake.disconnect();
  });

  testWidgets('RedisKeysView shows delete when the session is writable',
      (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const ['key_a'],
      dbSizeResult: 1,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 600,
            child: RedisKeysView(
              connection: fake,
              database: 0,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byTooltip('Delete key'), findsOneWidget);
    expect(find.text('Read-only session'), findsNothing);
    await fake.disconnect();
  });
}
