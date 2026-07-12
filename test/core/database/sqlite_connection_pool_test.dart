import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

ConnectionRow _row({int? id = 1}) => ConnectionRow(
      id: id,
      type: 'sqlite',
      name: 'test',
      host: '/path/to/test.db',
      createdAt: '2020-01-01T00:00:00Z',
    );

class FakeSqliteConnection extends SqliteConnection {
  FakeSqliteConnection({super.id = 1})
      : super(
          name: 'fake',
          path: '/path/to/test.db',
        );

  bool _connected = false;
  int connectCount = 0;
  int disconnectCount = 0;
  int forceCloseCount = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    connectCount++;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connected = false;
  }

  @override
  Future<void> forceClose() async {
    forceCloseCount++;
    _connected = false;
  }
}

void main() {
  group('SqliteConnectionPool', () {
    test('acquire increments refs and connects if needed', () async {
      final fake = FakeSqliteConnection();
      final pool = SqliteConnectionPool(
        createAndConnect: (row, {required mode}) async => fake,
      );

      final lease = await pool.acquire(_row(id: 1));
      expect(fake.connectCount, 1);
      expect(fake.isConnected, isTrue);

      lease.release();
    });

    test('evicts oldest idle entry when maxEntries reached', () async {
      final fakes = <int, FakeSqliteConnection>{};
      final pool = SqliteConnectionPool(
        maxEntries: 2,
        createAndConnect: (row, {required mode}) async {
          final c = FakeSqliteConnection(id: row.id ?? 1);
          fakes[row.id ?? 1] = c;
          return c;
        },
      );

      final l1 = await pool.acquire(_row(id: 1));
      l1.release();

      final l2 = await pool.acquire(_row(id: 2));
      l2.release();

      // At capacity (2 idle). Acquiring #3 should evict #1 (oldest idle).
      final l3 = await pool.acquire(_row(id: 3));
      expect(fakes[1]!.forceCloseCount, 1);
      l3.release();
    });

    test('throws StateError when all slots busy at maxEntries', () async {
      final pool = SqliteConnectionPool(
        maxEntries: 2,
        createAndConnect: (row, {required mode}) async =>
            FakeSqliteConnection(id: row.id ?? 1),
      );

      await pool.acquire(_row(id: 1)); // busy
      await pool.acquire(_row(id: 2)); // busy

      expect(
        () => pool.acquire(_row(id: 3)),
        throwsA(isA<StateError>()),
      );
    });

    test('rethrows SqliteConnectionException wrapped on acquire error', () async {
      final pool = SqliteConnectionPool(
        createAndConnect: (row, {required mode}) async {
          throw Exception('network boom');
        },
      );

      expect(
        () => pool.acquire(_row(id: 1)),
        throwsA(isA<SqliteConnectionException>()),
      );
    });

    test('disconnectAll force-closes all pooled entries', () async {
      final fake1 = FakeSqliteConnection(id: 1);
      final fake2 = FakeSqliteConnection(id: 2);
      var i = 0;
      final pool = SqliteConnectionPool(
        createAndConnect: (row, {required mode}) async => i++ == 0 ? fake1 : fake2,
      );

      await pool.acquire(_row(id: 1));
      await pool.acquire(_row(id: 2));
      await pool.disconnectAll();

      expect(fake1.forceCloseCount, 1);
      expect(fake2.forceCloseCount, 1);
    });
  });
}
