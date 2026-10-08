import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';

const _secret = 'Zero-Leak-Pw-91b4';

/// After the handshake a connection must not keep the password reachable
/// through its public getters (the "Zero-Leak" rule).
void main() {
  test('PostgreSQL drops password and connection string', () {
    final c = PostgresConnection(
      id: 1,
      name: 'pg',
      host: 'localhost',
      password: _secret,
      connectionString: 'postgresql://u:$_secret@localhost/db',
    );
    expect(c.password, _secret);
    c.scrubCredentials();
    expect(c.password, isNull);
    expect(c.connectionString, isNull);
  });

  test('MySQL drops password and connection string', () {
    final c = MysqlConnection(
      id: 2,
      name: 'my',
      host: 'localhost',
      password: _secret,
      connectionString: 'mysql://u:$_secret@localhost/db',
    );
    expect(c.password, _secret);
    c.scrubCredentials();
    expect(c.password, isNull);
    expect(c.connectionString, isNull);
  });

  test('Redis drops password and connection string', () {
    final c = RedisConnection(
      id: 3,
      name: 'redis',
      host: 'localhost',
      password: _secret,
      connectionString: 'redis://:$_secret@localhost',
    );
    expect(c.password, _secret);
    c.scrubCredentials();
    expect(c.password, isNull);
    expect(c.connectionString, isNull);
  });

  test('MongoDB drops password and connection string', () {
    final c = MongoConnection(
      id: 4,
      name: 'mongo',
      host: 'localhost',
      username: 'u',
      password: _secret,
    );
    expect(c.password, _secret);
    c.scrubCredentials();
    expect(c.password, isNull);
    expect(c.connectionString, isNull);
  });
}
