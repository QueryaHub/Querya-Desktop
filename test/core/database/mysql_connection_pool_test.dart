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
  bool? lastReadOnly;
  bool? openTransaction;

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
    lastReadOnly = readOnly;
  }

  @override
  Future<bool?> inOpenTransaction() async => openTransaction;
}

void main() {
  group('MysqlConnectionPool', () {
    test('acquire increments refs and connects if needed', () async {
      final fake = FakeMysqlConnection();
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async =>
            fake,
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

    test('tableWrite is a separate key from SQL readWrite', () async {
      final created = <FakeMysqlConnection>[];
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async {
          final c = FakeMysqlConnection();
          await c.connect();
          await c.setSessionReadOnly(mode.isReadOnlySession);
          created.add(c);
          return c;
        },
      );
      final r = _row();
      final sql = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.readWrite);
      final grid = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.tableWrite);
      final browse = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.readOnly);
      expect(identical(sql.connection, grid.connection), isFalse);
      expect(identical(sql.connection, browse.connection), isFalse);
      expect(created.length, 3);
      expect(
        pool.keyFor(1, 'app', MysqlSessionMode.tableWrite),
        '1::app::tableWrite',
      );
      expect((browse.connection as FakeMysqlConnection).lastReadOnly, isTrue);
      expect((grid.connection as FakeMysqlConnection).lastReadOnly, isFalse);
      sql.release();
      grid.release();
      browse.release();
    });

    test('interrupt of SQL readWrite does not kill tableWrite or readOnly',
        () async {
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async {
          final c = FakeMysqlConnection();
          await c.connect();
          return c;
        },
      );
      final r = _row();
      final sql = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.readWrite);
      final grid = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.tableWrite);
      final browse = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.readOnly);
      final sqlFake = sql.connection as FakeMysqlConnection;
      final gridFake = grid.connection as FakeMysqlConnection;
      final browseFake = browse.connection as FakeMysqlConnection;

      pool.interrupt(r, database: 'app', mode: MysqlSessionMode.readWrite);
      expect(sqlFake.forceCloseCount, 1);
      expect(gridFake.forceCloseCount, 0);
      expect(browseFake.forceCloseCount, 0);

      pool.interruptAllModes(r, database: 'app');
      expect(gridFake.forceCloseCount, 1);
      expect(browseFake.forceCloseCount, 1);
      sql.release();
      grid.release();
      browse.release();
    });

    test('hasOpenSqlTransaction reads the SQL slot only', () async {
      final pool = MysqlConnectionPool(
        createAndConnect: (row, {required database, required mode}) async {
          final c = FakeMysqlConnection();
          await c.connect();
          return c;
        },
      );
      final r = _row();
      expect(
        await pool.hasOpenSqlTransaction(r, database: 'app'),
        isFalse,
      );

      final sql = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.readWrite);
      (sql.connection as FakeMysqlConnection).openTransaction = true;
      expect(await pool.hasOpenSqlTransaction(r, database: 'app'), isTrue);
      expect(
        await pool.hasOpenSqlTransaction(r, database: 'other'),
        isFalse,
      );

      final grid = await pool.acquire(r,
          database: 'app', mode: MysqlSessionMode.tableWrite);
      (grid.connection as FakeMysqlConnection).openTransaction = true;
      (sql.connection as FakeMysqlConnection).openTransaction = false;
      expect(await pool.hasOpenSqlTransaction(r, database: 'app'), isFalse);
      sql.release();
      grid.release();
    });
  });
}
