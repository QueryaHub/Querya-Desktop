import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';

/// Counts outbound commands to prove [typesAndTtls] fires TYPE+TTL without
/// awaiting between keys (true pipeline enqueue).
class _CountingRedisFake extends RedisConnectionTestFake {
  _CountingRedisFake() : super(firstScanKeys: const []);

  final List<String> ops = [];

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    ops.add(args.first.toString().toUpperCase());
    // Delay so overlapping awaits would change order if callers awaited per key.
    await Future<void>.delayed(Duration.zero);
    return super.sendCommand(args);
  }
}

void main() {
  test('typesAndTtls enqueues all TYPE then all TTL before settling', () async {
    final fake = _CountingRedisFake();
    await fake.connect();

    final metas = await fake.typesAndTtls(['a', 'b', 'c']);

    expect(metas, hasLength(3));
    expect(metas.map((m) => m.type), everyElement('string'));
    expect(metas.map((m) => m.ttl), everyElement(-1));

    // All TYPE writes precede all TTL writes (single burst, not TYPE+TTL per key).
    expect(
      fake.ops,
      ['TYPE', 'TYPE', 'TYPE', 'TTL', 'TTL', 'TTL'],
    );
  });

  test('typesAndTtls returns empty for empty keys', () async {
    final fake = RedisConnectionTestFake();
    await fake.connect();
    expect(await fake.typesAndTtls(const []), isEmpty);
  });
}
