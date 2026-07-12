import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:postgres/postgres.dart' as pg;

class FakeSlowMysqlConnection extends MysqlConnection {
  FakeSlowMysqlConnection({super.id = 1})
      : super(
          name: 'fake_slow_mysql',
          host: 'localhost',
          port: 3306,
          database: 'testdb',
        );

  bool _connected = true;
  int forceCloseCount = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<IResultSet> execute(
    String sql, [
    Map<String, dynamic>? params,
    bool iterable = false,
  ]) async {
    await Future.delayed(const Duration(seconds: 10));
    throw Exception('should not reach here');
  }

  @override
  Future<void> forceClose() async {
    forceCloseCount++;
    _connected = false;
  }
}

class FakeSlowPostgresConnection extends PostgresConnection {
  FakeSlowPostgresConnection({super.id = 1})
      : super(
          name: 'fake_slow_pg',
          host: 'localhost',
          port: 5432,
          database: 'postgres',
        );

  bool _connected = true;
  int forceCloseCount = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<pg.Result> execute(String sql, {Duration? timeout}) async {
    await Future.delayed(const Duration(seconds: 10));
    throw Exception('should not reach here');
  }

  @override
  Future<void> forceClose() async {
    forceCloseCount++;
    _connected = false;
  }
}

class FakeSlowSqliteConnection extends SqliteConnection {
  FakeSlowSqliteConnection({super.id = 1})
      : super(
          name: 'fake_slow_sqlite',
          path: ':memory:',
        );

  bool _connected = true;
  int forceCloseCount = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<List<Map<String, Object?>>> execute(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    await Future.delayed(const Duration(seconds: 10));
    throw Exception('should not reach here');
  }

  @override
  Future<void> forceClose() async {
    forceCloseCount++;
    _connected = false;
  }
}

void main() {
  group('Connection Timeout Protocol Protection', () {
    test('MysqlConnection.executeWithTimeout force-closes on timeout', () async {
      final conn = FakeSlowMysqlConnection();
      expect(conn.isConnected, isTrue);

      try {
        await conn.executeWithTimeout(
          'SELECT sleep(100)',
          timeout: const Duration(milliseconds: 20),
        );
        fail('Should have thrown TimeoutException');
      } on TimeoutException {
        // Expected
      }

      await Future.delayed(const Duration(milliseconds: 10));
      expect(conn.forceCloseCount, 1);
      expect(conn.isConnected, isFalse);
    });

    test('PostgresConnection.executeWithTimeout force-closes on TimeoutException', () async {
      final conn = FakeSlowPostgresConnection();
      expect(conn.isConnected, isTrue);

      try {
        await conn.executeWithTimeout(
          'SELECT pg_sleep(100)',
          timeout: const Duration(milliseconds: 20),
        );
        fail('Should have thrown TimeoutException');
      } on TimeoutException {
        // Expected
      }

      await Future.delayed(const Duration(milliseconds: 10));
      expect(conn.forceCloseCount, 1);
      expect(conn.isConnected, isFalse);
    });

    test('SqliteConnection.executeWithTimeout force-closes on TimeoutException', () async {
      final conn = FakeSlowSqliteConnection();
      expect(conn.isConnected, isTrue);

      try {
        await conn.executeWithTimeout(
          'SELECT 1',
          timeout: const Duration(milliseconds: 20),
        );
        fail('Should have thrown TimeoutException');
      } on TimeoutException {
        // Expected
      }

      await Future.delayed(const Duration(milliseconds: 10));
      expect(conn.forceCloseCount, 1);
      expect(conn.isConnected, isFalse);
    });
  });
}
