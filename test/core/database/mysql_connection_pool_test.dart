import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/mysql_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

ConnectionRow _row({int? id = 1}) => ConnectionRow(
      id: id,
      type: 'mysql',
      name: 'test',
      createdAt: '2020-01-01T00:00:00Z',
    );

class FakeMysqlConnection extends MysqlConnection {
  FakeMysqlConnection({super.id = 1})
      : super(
          name: 'fake',
          host: 'localhost',
          port: 3306,
          database: 'testdb',
        );

  bool _connected = false;
  int connectCount = 0;
  int disconnectCount = 0;
  int forceCloseCount = 0;
  int setReadOnlyCount = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({int connectTimeoutMs = 10000}) async {
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

  @override
  Future<void> setSessionReadOnly(bool readOnly) async {
    setReadOnlyCount++;
  }
}

void main() {
  group('MysqlConnectionPool', () {
    test('acquire increments refs and connects if needed', () async {
      final fake = FakeMysqlConnection();
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async => fake,
      );

      final lease = await pool.acquire(_row(id: 1), database: 'testdb');
      expect(fake.connectCount, 1);
      expect(fake.setReadOnlyCount, 1);
      expect(fake.isConnected, isTrue);

      lease.release();
    });

    test('wraps unknown exceptions in MysqlConnectionException', () async {
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async {
          throw Exception('Connection refused');
        },
      );

      expect(
        () => pool.acquire(_row(id: 1), database: 'testdb'),
        throwsA(isA<MysqlConnectionException>()),
      );
    });

    test('rethrows StateError directly when pool exhausted', () async {
      final pool = MysqlConnectionPool(
        maxEntries: 1,
        createAndConnect: (row, {required database, required mode}) async =>
            FakeMysqlConnection(id: row.id ?? 1),
      );

      await pool.acquire(_row(id: 1), database: 'db1'); // busy

      expect(
        () => pool.acquire(_row(id: 2), database: 'db2'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
