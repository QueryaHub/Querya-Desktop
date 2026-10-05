import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
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

  testWidgets('RedisKeysView Delete Cancel does not send DEL', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(800, 700));
    final fake = _DelTrackingFake(
      firstScanKeys: const ['key_a'],
      dbSizeResult: 1,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 800,
            height: 700,
            child: RedisKeysView(
              connection: fake,
              database: 0,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete key'));
    await tester.pumpAndSettle();

    expect(find.text('DEL key_a'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.deleted, isEmpty);
    expect(find.text('key_a'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeysView shows binary SCAN keys as hex, not List.toString',
      (tester) async {
    final fake = RedisConnectionTestFake(
      firstScanKeys: const ['ascii'],
      binaryScanKeys: const [
        [0xff, 0xfe],
      ],
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
    await tester.pumpAndSettle();

    expect(find.text('ascii'), findsOneWidget);
    expect(find.text('0xfffe'), findsOneWidget);
    expect(find.text('[255, 254]'), findsNothing);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeysView loops through empty SCAN batch until keys are found',
      (tester) async {
    final fake = _MultiStepScanFake(
      steps: [
        // Step 1: empty keys, next cursor 10
        (nextCursor: 10, keys: <String>[]),
        // Step 2: found key, next cursor 0
        (nextCursor: 0, keys: <String>['target_key']),
      ],
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

    expect(find.text('target_key'), findsOneWidget);
    expect(fake.scanCallCount, 2);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeysView shows Continue scanning when empty after iteration limit',
      (tester) async {
    // 10 empty steps with cursor > 0, then 1 step with keys
    final fake = _MultiStepScanFake(
      steps: [
        for (var i = 1; i <= 10; i++) (nextCursor: i, keys: <String>[]),
        (nextCursor: 0, keys: <String>['late_key']),
      ],
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

    expect(find.text('No keys found in scanned range'), findsOneWidget);
    expect(find.text('Continue scanning'), findsOneWidget);
    expect(fake.scanCallCount, 10);

    // Tap continue scanning
    await tester.tap(find.text('Continue scanning'));
    await tester.pumpAndSettle();

    expect(find.text('late_key'), findsOneWidget);
    expect(fake.scanCallCount, 11);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeysView toggles between Flat and Tree view modes and invokes onKeyTap',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(900, 700));
    final fake = RedisConnectionTestFake(
      firstScanKeys: const [
        'user:profile',
        'user:settings',
        'standalone',
      ],
      dbSizeResult: 3,
    );
    await fake.connect();

    String? tappedKey;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 900,
            height: 700,
            child: RedisKeysView(
              connection: fake,
              database: 0,
              onKeyTap: (key, type) => tappedKey = key.label,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In flat mode initially
    expect(find.text('Flat'), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('user:profile'), findsOneWidget);
    expect(find.text('standalone'), findsOneWidget);

    // Switch to Tree view
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();

    // Verify folder hierarchy
    expect(find.text('user'), findsOneWidget);
    expect(find.text('2 keys'), findsOneWidget);
    expect(find.text('profile'), findsOneWidget);
    expect(find.text('settings'), findsOneWidget);
    expect(find.text('standalone'), findsOneWidget);

    // Tap a leaf key
    await tester.tap(find.text('profile'));
    await tester.pumpAndSettle();
    expect(tappedKey, 'user:profile');

    // Switch back to Flat view
    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle();
    expect(find.text('user:profile'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets('RedisKeysView tree view collapse and expand folder',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(900, 700));
    final fake = RedisConnectionTestFake(
      firstScanKeys: const [
        'user:profile',
        'user:settings',
      ],
      dbSizeResult: 2,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 900,
            height: 700,
            child: RedisKeysView(
              connection: fake,
              database: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Tree view
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();

    expect(find.text('user'), findsOneWidget);
    expect(find.text('profile'), findsOneWidget);

    // Collapse 'user' folder
    await tester.tap(find.text('user'));
    await tester.pumpAndSettle();

    expect(find.text('user'), findsOneWidget);
    expect(find.text('profile'), findsNothing);

    // Expand 'user' folder again
    await tester.tap(find.text('user'));
    await tester.pumpAndSettle();

    expect(find.text('profile'), findsOneWidget);
    await fake.disconnect();
  });

  testWidgets(
      'RedisKeysView tree view folder delete cancels and executes delMany',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(900, 700));
    final fake = _DelTrackingFake(
      firstScanKeys: const [
        'user:profile',
        'user:settings',
        'standalone',
      ],
      dbSizeResult: 3,
    );
    await fake.connect();

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 900,
            height: 700,
            child: RedisKeysView(
              connection: fake,
              database: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Tree view
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();

    final deleteFolderButton = find.byTooltip('Delete folder (2 keys)');
    expect(deleteFolderButton, findsOneWidget);

    // Tap delete folder, then Cancel
    await tester.tap(deleteFolderButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('DEL user:profile'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.deleted, isEmpty);

    // Tap delete folder, then Confirm execution
    await tester.tap(deleteFolderButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Execute Destructive Statement'));
    await tester.pumpAndSettle();

    expect(fake.deleted, contains('user:profile'));
    expect(fake.deleted, contains('user:settings'));
    expect(find.text('user'), findsNothing);
    expect(find.text('standalone'), findsOneWidget);
    await fake.disconnect();
  });
}

class _DelTrackingFake extends RedisConnectionTestFake {
  _DelTrackingFake({super.firstScanKeys, super.dbSizeResult});

  final deleted = <String>[];

  @override
  Future<int> del(Object key) async {
    deleted.add(key is RedisBulkValue ? key.label : key.toString());
    return super.del(key);
  }

  @override
  Future<int> delMany(Iterable<Object> keys) async {
    for (final k in keys) {
      deleted.add(k is RedisBulkValue ? k.label : k.toString());
    }
    return super.delMany(keys);
  }
}

class _MultiStepScanFake extends RedisConnectionTestFake {
  _MultiStepScanFake({
    required this.steps,
    super.dbSizeResult,
  });

  final List<({int nextCursor, List<String> keys})> steps;
  int scanCallCount = 0;

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    final op = args.first.toString().toUpperCase();
    if (op == 'SCAN') {
      final stepIndex = scanCallCount;
      scanCallCount++;
      if (stepIndex < steps.length) {
        final step = steps[stepIndex];
        return [step.nextCursor, step.keys];
      }
      return [0, <String>[]];
    }
    return super.sendCommand(args);
  }
}
