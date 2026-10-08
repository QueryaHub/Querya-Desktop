import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/features/redis/redis_key_editor.dart';
import 'package:querya_desktop/features/redis/redis_keys_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

/// Remembers EXPIRE / PERSIST and reports the resulting TTL back.
class _TtlRedis extends RedisConnectionTestFake {
  _TtlRedis({super.firstScanKeys, super.dbSizeResult, super.getResult});

  int ttlValue = -1;
  final List<List<dynamic>> writes = [];

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    final op = args.first.toString().toUpperCase();
    if (op == 'TTL') return ttlValue;
    if (op == 'EXPIRE') {
      writes.add(args);
      ttlValue = int.parse(args.last.toString());
      return 1;
    }
    if (op == 'PERSIST') {
      writes.add(args);
      ttlValue = -1;
      return 1;
    }
    return super.sendCommand(args);
  }
}

/// Keys tree on the left, editor of the tapped key on the right — the same
/// wiring the Redis explorer uses.
class _Explorer extends material.StatefulWidget {
  const _Explorer({required this.connection});

  final RedisConnection connection;

  @override
  material.State<_Explorer> createState() => _ExplorerState();
}

class _ExplorerState extends material.State<_Explorer> {
  RedisBulkValue? _key;
  String _type = 'string';

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      body: material.Row(
        children: [
          material.SizedBox(
            width: 360,
            child: RedisKeysView(
              connection: widget.connection,
              database: 0,
              onKeyTap: (key, type) => setState(() {
                _key = key;
                _type = type;
              }),
            ),
          ),
          material.Expanded(
            child: _key == null
                ? const material.SizedBox.shrink()
                : RedisKeyEditor(
                    key: material.ValueKey(_key!.label),
                    connection: widget.connection,
                    database: 0,
                    keyName: _key!.label,
                    keyArg: _key!.commandArg,
                    keyType: _type,
                  ),
          ),
        ],
      ),
    );
  }
}

void main() {
  Future<void> open(WidgetTester tester, RedisConnection redis) async {
    await redis.connect();
    addTearDown(redis.disconnect);
    await tester.binding.setSurfaceSize(const material.Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(child: _Explorer(connection: redis)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keys group into a folder tree and a leaf opens its editor',
      timeout: _timeout, (tester) async {
    await open(
      tester,
      _TtlRedis(
        firstScanKeys: const ['user:profile', 'user:settings', 'standalone'],
        dbSizeResult: 3,
        getResult: 'hello',
      ),
    );

    expect(find.text('user:profile'), findsOneWidget);

    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    expect(find.text('user'), findsOneWidget);
    expect(find.text('2 keys'), findsOneWidget);
    expect(find.text('profile'), findsOneWidget);

    await tester.tap(find.text('profile'));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Set TTL applies EXPIRE and shows the new expiry',
      timeout: _timeout, (tester) async {
    final redis = _TtlRedis(
      firstScanKeys: const ['session:1'],
      dbSizeResult: 1,
      getResult: 'token',
    );
    await open(tester, redis);

    await tester.tap(find.text('session:1'));
    await tester.pumpAndSettle();
    expect(find.text('No expiry'), findsOneWidget);

    await tester.tap(find.byTooltip('Set TTL'));
    await tester.pumpAndSettle();
    expect(find.text('Enter TTL in seconds (0 to remove)'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(QueryaModalDialog),
        matching: find.byType(TextField),
      ),
      '120',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(redis.writes, hasLength(1));
    expect(redis.writes.single.first, 'EXPIRE');
    expect(find.text('TTL set to 120 seconds'), findsOneWidget);
    expect(find.text('2m 0s'), findsOneWidget);
    // Let the success banner's auto-clear timer finish.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('TTL 0 removes the expiry with PERSIST', timeout: _timeout,
      (tester) async {
    final redis = _TtlRedis(
      firstScanKeys: const ['session:1'],
      dbSizeResult: 1,
      getResult: 'token',
    )..ttlValue = 300;
    await open(tester, redis);

    await tester.tap(find.text('session:1'));
    await tester.pumpAndSettle();
    expect(find.text('5m 0s'), findsOneWidget);

    await tester.tap(find.byTooltip('Set TTL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(QueryaModalDialog),
        matching: find.byType(TextField),
      ),
      '0',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(redis.writes.single.first, 'PERSIST');
    expect(find.text('TTL removed'), findsOneWidget);
    expect(find.text('No expiry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
