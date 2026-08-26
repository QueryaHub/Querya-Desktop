import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('ConnectionRow secret scrubbing', () {
    test('withoutSecrets clears password and connectionString while keeping all metadata', () {
      const row = ConnectionRow(
        id: 42,
        type: 'postgresql',
        name: 'Production DB',
        host: 'db.example.com',
        port: 5432,
        username: 'admin',
        password: 'super_secret_password_123',
        databaseName: 'customers',
        authSource: 'admin',
        useSSL: true,
        connectionString: 'postgresql://admin:super_secret_password_123@db.example.com/customers',
        folderId: 3,
        sortOrder: 1,
        createdAt: '2026-08-26T12:00:00Z',
      );

      expect(row.hasPassword, isTrue);
      expect(row.hasConnectionString, isTrue);
      expect(row.hasSecrets, isTrue);

      final scrubbed = row.withoutSecrets();

      expect(scrubbed.id, 42);
      expect(scrubbed.type, 'postgresql');
      expect(scrubbed.name, 'Production DB');
      expect(scrubbed.host, 'db.example.com');
      expect(scrubbed.port, 5432);
      expect(scrubbed.username, 'admin');
      expect(scrubbed.databaseName, 'customers');
      expect(scrubbed.authSource, 'admin');
      expect(scrubbed.useSSL, isTrue);
      expect(scrubbed.folderId, 3);
      expect(scrubbed.sortOrder, 1);
      expect(scrubbed.createdAt, '2026-08-26T12:00:00Z');

      // Secrets must be null
      expect(scrubbed.password, isNull);
      expect(scrubbed.connectionString, isNull);
      expect(scrubbed.hasPassword, isFalse);
      expect(scrubbed.hasConnectionString, isFalse);
      expect(scrubbed.hasSecrets, isFalse);
    });

    test('toPersistenceMap does not include plaintext secrets for SQLite storage', () {
      const row = ConnectionRow(
        id: 1,
        type: 'mysql',
        name: 'App MySQL',
        host: '127.0.0.1',
        port: 3306,
        username: 'root',
        password: 'secret_root_password',
        databaseName: 'app',
        connectionString: 'mysql://root:secret_root_password@127.0.0.1:3306/app',
        createdAt: '2026-08-26T12:00:00Z',
      );

      final map = row.toPersistenceMap();
      expect(map['password'], isNull);
      expect(map['connection_string'], isNull);
      expect(map['name'], 'App MySQL');
      expect(map['username'], 'root');
    });
  });

  group('Database driver connection secret scrubbing', () {
    test('PostgresConnection.scrubCredentials zeroes password and connectionString', () {
      final conn = PostgresConnection(
        id: 10,
        name: 'PG Connection',
        host: 'localhost',
        port: 5432,
        username: 'postgres',
        password: 'secret_pg_password',
        connectionString: 'postgresql://postgres:secret_pg_password@localhost/postgres',
      );

      expect(conn.password, 'secret_pg_password');
      expect(conn.connectionString, contains('secret_pg_password'));

      conn.scrubCredentials();

      expect(conn.password, isNull);
      expect(conn.connectionString, isNull);
    });

    test('MysqlConnection.scrubCredentials zeroes password and connectionString', () {
      final conn = MysqlConnection(
        id: 11,
        name: 'MySQL Connection',
        host: 'localhost',
        port: 3306,
        username: 'user',
        password: 'secret_mysql_password',
        connectionString: 'mysql://user:secret_mysql_password@localhost/app',
      );

      expect(conn.password, 'secret_mysql_password');
      expect(conn.connectionString, contains('secret_mysql_password'));

      conn.scrubCredentials();

      expect(conn.password, isNull);
      expect(conn.connectionString, isNull);
    });

    test('RedisConnection.scrubCredentials zeroes password and connectionString', () {
      final conn = RedisConnection(
        id: 12,
        name: 'Redis Connection',
        host: 'localhost',
        port: 6379,
        password: 'secret_redis_auth',
        connectionString: 'redis://:secret_redis_auth@localhost:6379',
      );

      expect(conn.password, 'secret_redis_auth');
      expect(conn.connectionString, contains('secret_redis_auth'));

      conn.scrubCredentials();

      expect(conn.password, isNull);
      expect(conn.connectionString, isNull);
    });

    test('MongoConnection.scrubCredentials zeroes password and connectionString', () {
      final conn = MongoConnection(
        id: 13,
        name: 'Mongo Connection',
        host: 'localhost',
        port: 27017,
        username: 'mongo_user',
        password: 'secret_mongo_password',
        connectionString: 'mongodb://mongo_user:secret_mongo_password@localhost:27017/admin',
      );

      expect(conn.password, 'secret_mongo_password');
      expect(conn.connectionString, contains('secret_mongo_password'));

      conn.scrubCredentials();

      expect(conn.password, isNull);
      expect(conn.connectionString, isNull);
    });
  });
}
