import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/redis/redis_keys_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RedisKeysView lists keys from ListView after load', (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const ['key_a', 'key_b'],
      dbSizeResult: 2,
    );
    await fake.connect();

    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: material.Scaffold(
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
      ShadcnApp(
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: material.SizedBox(
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
}
