import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

ConnectionRow _row({int? id = 1}) => ConnectionRow(
      id: id,
      type: 'postgresql',
      name: 'test',
      createdAt: '2020-01-01T00:00:00Z',
    );

/// In-memory stand-in: no TCP, tracks refcount-related calls.
class FakePostgresConnection extends PostgresConnection {
  FakePostgresConnection({super.id = 1})
      : super(
          name: 'fake',
          host: 'localhost',
          port: 5432,
          database: 'postgres',
        );

  bool _connected = false;
  int connectCount = 0;
  int disconnectCount = 0;
  int forceCloseCount = 0;
  int setReadOnlyCount = 0;
  bool? lastReadOnly;

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

  @override
  Future<void> setSessionReadOnly(bool readOnly) async {
    setReadOnlyCount++;
    lastReadOnly = readOnly;
  }
}

void main() {
  group('PostgresConnectionPool keys', () {
    test('different databases get different pool slots', () async {
      final created = <FakePostgresConnection>[];
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection(id: row.id ?? 0);
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        created.add(c);
        return c;
      }

      final pool = PostgresConnectionPool(createAndConnect: factory);
      final r = _row();
      final a = await pool.acquire(r, database: 'db_a');
      final b = await pool.acquire(r, database: 'db_b');
      expect(identical(a.connection, b.connection), isFalse);
      expect(created.length, 2);
      a.release();
      b.release();
    });

    test('readOnly vs readWrite are different keys', () async {
      final created = <FakePostgresConnection>[];
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection();
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        created.add(c);
        return c;
      }

      final pool = PostgresConnectionPool(createAndConnect: factory);
      final r = _row();
      final ro = await pool.acquire(r, database: 'postgres', mode: PgSessionMode.readOnly);
      final rw = await pool.acquire(r, database: 'postgres', mode: PgSessionMode.readWrite);
      expect(identical(ro.connection, rw.connection), isFalse);
      expect(created.length, 2);
      ro.release();
      rw.release();
    });

    test('keyFor matches pool slot identity', () {
      final pool = PostgresConnectionPool(
        createAndConnect: (_, {required database, required mode}) async =>
            throw StateError('unused'),
      );
      expect(
        pool.keyFor(1, 'postgres', PgSessionMode.readOnly),
        '1::postgres::readOnly',
      );
      expect(
        pool.keyFor(null, 'postgres', PgSessionMode.readWrite),
        '0::postgres::readWrite',
      );
    });
  });

  group('PostgresConnectionPool refcount & reuse', () {
    test('second acquire reuses same connection without new factory', () async {
      FakePostgresConnection? sole;
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        sole ??= FakePostgresConnection();
        final c = sole!;
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        return c;
      }

      final pool = PostgresConnectionPool(createAndConnect: factory);
      final r = _row();
      final l1 = await pool.acquire(r, database: 'postgres');
      final l2 = await pool.acquire(r, database: 'postgres');
      expect(identical(l1.connection, l2.connection), isTrue);
      expect((l1.connection as FakePostgresConnection).connectCount, 1);
      l1.release();
      l2.release();
    });

    test('release then quick acquire cancels idle timer and keeps connection',
        () async {
      FakePostgresConnection? sole;
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        sole ??= FakePostgresConnection();
        final c = sole!;
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        return c;
      }

      final pool = PostgresConnectionPool(
        createAndConnect: factory,
        idleDisposeDelay: const Duration(milliseconds: 50),
      );
      final r = _row();

      final first = await pool.acquire(r, database: 'postgres');
      first.release();
      await Future<void>.delayed(Duration.zero);
      final second = await pool.acquire(r, database: 'postgres');
      // If idle timer were not cancelled, disconnect would run after 50ms.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sole!.disconnectCount, 0);
      second.release();
    });
  });

  group('PostgresConnectionPool idle dispose', () {
    test('after last release, idle delay triggers disconnect', () async {
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection();
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        return c;
      }

      final pool = PostgresConnectionPool(
        createAndConnect: factory,
        idleDisposeDelay: const Duration(milliseconds: 20),
      );
      final r = _row();

      final lease = await pool.acquire(r, database: 'postgres');
      final fake = lease.connection as FakePostgresConnection;
      lease.release();
      expect(fake.disconnectCount, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fake.disconnectCount, 1);
    });
  });

  group('PostgresConnectionPool interrupt & disconnectAll', () {
    test('interrupt removes entry and forceCloses', () async {
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection();
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        return c;
      }

      final pool = PostgresConnectionPool(createAndConnect: factory);
      final r = _row();
      final lease = await pool.acquire(r, database: 'postgres');
      final fake = lease.connection as FakePostgresConnection;
      pool.interrupt(r, database: 'postgres');
      expect(fake.forceCloseCount, 1);
      lease.release(); // no-op harm: pool entry already gone
      final lease2 = await pool.acquire(r, database: 'postgres');
      expect(identical(lease2.connection, fake), isFalse);
      lease2.release();
    });

    test('disconnectAll forceCloses every pooled connection', () async {
      final fakes = <FakePostgresConnection>[];
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection(id: row.id ?? 0);
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        fakes.add(c);
        return c;
      }

      final pool = PostgresConnectionPool(createAndConnect: factory);
      final a = await pool.acquire(_row(id: 1), database: 'postgres');
      final b = await pool.acquire(_row(id: 2), database: 'postgres');
      await pool.disconnectAll();
      expect(fakes.every((f) => f.forceCloseCount == 1), isTrue);
      a.release();
      b.release();
    });
  });

  group('PgLease idempotency', () {
    test('double release does not double-decrement refs', () async {
      Future<PostgresConnection> factory(
        ConnectionRow row, {
        required String database,
        required PgSessionMode mode,
      }) async {
        final c = FakePostgresConnection();
        await c.connect();
        await c.setSessionReadOnly(mode == PgSessionMode.readOnly);
        return c;
      }

      final pool = PostgresConnectionPool(
        createAndConnect: factory,
        idleDisposeDelay: const Duration(milliseconds: 15),
      );
      final lease = await pool.acquire(_row(), database: 'postgres');
      final fake = lease.connection as FakePostgresConnection;
      lease.release();
      lease.release();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fake.disconnectCount, 1);
    });
  });
}
