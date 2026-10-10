import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';

void main() {
  group('SSH tunnel failures (#1305)', () {
    test('a rejected SSH login is not the database refusing the credentials',
        () {
      final e = mapDatabaseError(
        const SshAuthenticationException(
            'SSH authentication failed for deploy@bastion.example: rejected'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isNot(isA<AuthFailedException>()));
      expect(e.message, contains('deploy@bastion.example'));
      expect(e.remediationHint, contains('SSH'));
    });

    test('the one-line text keeps the host and points at the tunnel settings',
        () {
      final text = describeDatabaseError(
        const SshAuthenticationException(
            'SSH authentication failed for deploy@bastion.example: rejected'),
        driver: DatabaseDriver.postgres,
      );
      expect(text, contains('deploy@bastion.example'));
      expect(text, contains('SSH tunnel settings'));
      expect(text, isNot(contains('username and password in the connection')));
    });

    test('a connection failure of the tunnel is unreachable, not authentication',
        () {
      final e = mapDatabaseError(
        const SshConnectionException(
            'The SSH connection to bastion.example:22 failed: reset'),
      );
      expect(e, isA<HostUnreachableException>());
      expect(e.message, contains('bastion.example:22'));
    });

    test('a host key mismatch says not to connect', () {
      final e = mapDatabaseError(const SshHostKeyMismatchException(
          'SSH host key verification failed for bastion.example.'));
      expect(e.remediationHint, contains('do not connect'));
    });

    test('a database authentication failure behind a tunnel is still one', () {
      final e = mapDatabaseError(
        Exception('password authentication failed for user "bob"'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<AuthFailedException>());
    });
  });

  group('lost sessions and TLS (#1316)', () {
    test('a reset or closed session is a lost connection, not a refusal', () {
      for (final text in [
        'SocketException: Connection reset by peer (OS Error: Connection '
            'reset by peer, errno = 104)',
        'SocketException: Broken pipe',
        'ERROR: terminating connection due to administrator command',
        'Lost connection to MySQL server during query',
        'PgException: Connection is closed',
      ]) {
        final e = mapDatabaseError(Exception(text));
        expect(e, isA<ConnectionLostException>(), reason: text);
        expect(e, isNot(isA<HostUnreachableException>()), reason: text);
        expect(e.remediationHint, contains('Reconnect'));
      }
    });

    test('a refused connection is still unreachable', () {
      final e = mapDatabaseError(const SocketException(
          'Connection refused (OS Error: Connection refused, errno = 111)'));
      expect(e, isA<HostUnreachableException>());
    });

    test('certificate and handshake failures point at the SSL settings', () {
      for (final error in <Object>[
        const HandshakeException(
            'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
            'self signed certificate)'),
        Exception('TlsException: unknown ca'),
        Exception('WRONG_VERSION_NUMBER: wrong version number'),
      ]) {
        final e = mapDatabaseError(error, driver: DatabaseDriver.postgres);
        expect(e, isA<TlsFailureException>(), reason: '$error');
        expect(e.remediationHint, contains('SSL mode'));
        expect(e.remediationHint, contains('root certificate'));
      }
    });

    test('an authentication failure is not taken for TLS', () {
      final e = mapDatabaseError(
        Exception('password authentication failed for user "bob"'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<AuthFailedException>());
    });
  });

  group('missing columns (#1310)', () {
    test('a column of an existing table is not a missing table', () {
      final e = mapDatabaseError(
        Exception('ERROR: column "nickname" of relation "users" does not exist'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<ColumnNotFoundException>());
      expect((e as ColumnNotFoundException).columnName, 'nickname');
      expect(e.tableName, 'users');
      expect(e.message, 'Column "nickname" does not exist in "users"');
      expect(e, isNot(isA<TableNotFoundException>()));
    });

    test('PostgreSQL, MySQL and SQLite wordings without a table', () {
      for (final (text, driver, name) in [
        ('column "price" does not exist', DatabaseDriver.postgres, 'price'),
        (
          "Unknown column 'price' in 'field list'",
          DatabaseDriver.mysql,
          'price'
        ),
        ('no such column: orders.price', DatabaseDriver.sqlite, 'orders.price'),
      ]) {
        final e = mapDatabaseError(Exception(text), driver: driver);
        expect(e, isA<ColumnNotFoundException>(), reason: text);
        expect((e as ColumnNotFoundException).columnName, name);
      }
    });

    test('a missing relation is still a missing table', () {
      final e = mapDatabaseError(
        Exception('ERROR: relation "orders" does not exist'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<TableNotFoundException>());
      expect((e as TableNotFoundException).tableName, 'orders');
    });
  });

  group('mapDatabaseError PostgreSQL', () {
    test('wrong password is AuthFailedException', () {
      final e = mapDatabaseError(
        PostgresConnectionException(
          'Failed to connect',
          cause: Exception('password authentication failed for user "bob"'),
        ),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<AuthFailedException>());
      expect(e.remediationHint, isNotEmpty);
    });

    test('missing database is DatabaseNotFoundException with the name', () {
      final e = mapDatabaseError(
        Exception('database "shop" does not exist'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<DatabaseNotFoundException>());
      expect((e as DatabaseNotFoundException).databaseName, 'shop');
    });

    test('missing relation is TableNotFoundException keeping the name', () {
      final e = mapDatabaseError(
        Exception('relation "public.Users" does not exist'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<TableNotFoundException>());
      expect((e as TableNotFoundException).tableName, 'public.Users');
    });

    test('syntax error', () {
      final e = mapDatabaseError(
        Exception('syntax error at or near "SELEC"'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<QuerySyntaxException>());
    });

    test('lock timeout', () {
      final e = mapDatabaseError(
        Exception('canceling statement due to lock timeout'),
        driver: DatabaseDriver.postgres,
      );
      expect(e, isA<LockTimeoutException>());
    });
  });

  group('mapDatabaseError MySQL', () {
    test('access denied', () {
      final e = mapDatabaseError(
        MysqlConnectionException(
          'Failed to connect',
          cause: Exception("Access denied for user 'root'@'localhost'"),
        ),
        driver: DatabaseDriver.mysql,
      );
      expect(e, isA<AuthFailedException>());
    });

    test('unknown database', () {
      final e = mapDatabaseError(
        Exception("Unknown database 'nope'"),
        driver: DatabaseDriver.mysql,
      );
      expect(e, isA<DatabaseNotFoundException>());
    });

    test("table doesn't exist", () {
      final e = mapDatabaseError(
        Exception("Table 'shop.orders' doesn't exist"),
        driver: DatabaseDriver.mysql,
      );
      expect(e, isA<TableNotFoundException>());
      expect((e as TableNotFoundException).tableName, 'shop.orders');
    });

    test('syntax error', () {
      final e = mapDatabaseError(
        Exception('You have an error in your SQL syntax; check the manual'),
        driver: DatabaseDriver.mysql,
      );
      expect(e, isA<QuerySyntaxException>());
    });

    test('lock wait timeout', () {
      final e = mapDatabaseError(
        Exception('Lock wait timeout exceeded; try restarting transaction'),
        driver: DatabaseDriver.mysql,
      );
      expect(e, isA<LockTimeoutException>());
    });
  });

  group('mapDatabaseError SQLite', () {
    test('no such table', () {
      final e = mapDatabaseError(
        SqliteConnectionException(
          'Query failed',
          cause: Exception('no such table: notes'),
        ),
        driver: DatabaseDriver.sqlite,
      );
      expect(e, isA<TableNotFoundException>());
      expect((e as TableNotFoundException).tableName, 'notes');
    });

    test('database is locked', () {
      final e = mapDatabaseError(
        Exception('database is locked'),
        driver: DatabaseDriver.sqlite,
      );
      expect(e, isA<LockTimeoutException>());
    });

    test('syntax error near token', () {
      final e = mapDatabaseError(
        Exception('near "FORM": syntax error'),
        driver: DatabaseDriver.sqlite,
      );
      expect(e, isA<QuerySyntaxException>());
    });
  });

  group('mapDatabaseError MongoDB', () {
    test('authentication failed', () {
      final e = mapDatabaseError(
        StateError('Authentication failed.'),
        driver: DatabaseDriver.mongodb,
      );
      expect(e, isA<AuthFailedException>());
    });

    test('socket exception is HostUnreachableException', () {
      final e = mapDatabaseError(
        const SocketException('Connection refused'),
        driver: DatabaseDriver.mongodb,
      );
      expect(e, isA<HostUnreachableException>());
    });
  });

  group('mapDatabaseError Redis', () {
    test('WRONGPASS', () {
      final e = mapDatabaseError(
        RedisConnectionException(
          'WRONGPASS invalid username-password pair or user is disabled.',
        ),
        driver: DatabaseDriver.redis,
      );
      expect(e, isA<AuthFailedException>());
      expect(e.remediationHint, contains('requirepass'));
    });

    test('NOAUTH', () {
      final e = mapDatabaseError(
        Exception('NOAUTH Authentication required.'),
        driver: DatabaseDriver.redis,
      );
      expect(e, isA<AuthFailedException>());
    });

    test('ERR syntax error', () {
      final e = mapDatabaseError(
        RedisConnectionException('ERR syntax error'),
        driver: DatabaseDriver.redis,
      );
      expect(e, isA<QuerySyntaxException>());
    });
  });

  group('mapDatabaseError generic', () {
    test('TimeoutException is ConnectionTimeoutException', () {
      final e = mapDatabaseError(TimeoutException('connect'));
      expect(e, isA<ConnectionTimeoutException>());
    });

    test('failed host lookup is HostUnreachableException', () {
      final e = mapDatabaseError(
        const SocketException('Failed host lookup: "db.invalid"'),
      );
      expect(e, isA<HostUnreachableException>());
    });

    test('already mapped exceptions are returned unchanged', () {
      const original = AuthFailedException('nope');
      expect(identical(mapDatabaseError(original), original), isTrue);
    });

    test('unrecognized errors become UnknownDatabaseException', () {
      final e = mapDatabaseError(const FormatException('bad connection'));
      expect(e, isA<UnknownDatabaseException>());
      expect(e.originalError, isA<FormatException>());
    });

    test('displayText appends the remediation hint', () {
      const e = AuthFailedException('Authentication failed',
          remediationHint: 'Check the password');
      expect(e.displayText, 'Authentication failed. Check the password');
      expect(e.toString(), e.displayText);
    });
  });

  group('describeDatabaseError', () {
    test('uses message and hint for recognized errors', () {
      final text = describeDatabaseError(
        Exception('password authentication failed for user "x"'),
        driver: DatabaseDriver.postgres,
      );
      expect(text, startsWith('Authentication failed'));
      expect(text, contains('username and password'));
    });

    test('keeps the original text for unrecognized errors', () {
      const err = FormatException('bad connection string');
      expect(describeDatabaseError(err), err.toString());
    });
  });

  group('rethrowMappedDatabaseError', () {
    test('throws the mapped exception for recognized errors', () {
      expect(
        () => rethrowMappedDatabaseError(
          const SocketException('Connection refused'),
          StackTrace.current,
          driver: DatabaseDriver.redis,
        ),
        throwsA(isA<HostUnreachableException>()),
      );
    });

    test('rethrows unrecognized errors unchanged', () {
      expect(
        () => rethrowMappedDatabaseError(
          const FormatException('x'),
          StackTrace.current,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
