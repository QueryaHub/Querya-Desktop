import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connection_url_parser.dart';

void main() {
  group('parseConnectionUrlInput', () {
    test('returns error for empty input', () {
      final result = parseConnectionUrlInput('  ');
      expect(result.row, isNull);
      expect(result.error, 'URL/URI is required.');
    });

    test('a password with special characters written as is imports (#1315)',
        () {
      for (final (url, password, host, db) in [
        ('postgres://user:p@ss@db.example:5432/app', 'p@ss', 'db.example', 'app'),
        ('postgres://user:p#ss@db.example/app', 'p#ss', 'db.example', 'app'),
        ('mysql://root:pa/ss@localhost/shop', 'pa/ss', 'localhost', 'shop'),
        ('redis://default:a?b@cache.example:6380', 'a?b', 'cache.example', null),
      ]) {
        final r = parseConnectionUrlInput(url);
        expect(r.error, isNull, reason: url);
        final row = r.row!;
        expect(row.password, password, reason: url);
        expect(row.host, host, reason: url);
        expect(row.databaseName, db, reason: url);
        // The stored string is the encoded, valid one.
        expect(Uri.tryParse(row.connectionString!), isNotNull, reason: url);
      }
    });

    test('an already encoded password is not encoded twice', () {
      final row =
          parseConnectionUrlInput('postgres://u:p%40ss@h:5432/db').row!;
      expect(row.password, 'p@ss');
      expect(row.connectionString, 'postgres://u:p%40ss@h:5432/db');
    });

    test('a URL that stays invalid names percent-encoding', () {
      final r = parseConnectionUrlInput('not a url@x');
      expect(r.row, isNull);
      expect(r.error, contains('percent-encode'));
      expect(parseConnectionUrlInput('not a url').error,
          'Invalid URL/URI format.');
    });

    test('a Windows SQLite file URL has no slash before the drive', () {
      final row = parseConnectionUrlInput('sqlite:///C:/data/app.db').row!;
      expect(row.host, 'C:/data/app.db');
      // A POSIX path keeps its slash.
      expect(parseConnectionUrlInput('sqlite:///tmp/test.db').row!.host,
          '/tmp/test.db');
    });

    test('an IPv6 host is bracketed in the default name', () {
      final row =
          parseConnectionUrlInput('postgresql://u:pw@[::1]:5432').row!;
      expect(row.host, '::1');
      expect(row.name, 'PostgreSQL: [::1]:5432');
    });

    test('imports a MongoDB replica-set string with several hosts (#1309)',
        () {
      const url = 'mongodb://app:s3cret@db1.example:27017,db2.example:27018'
          '/shop?replicaSet=rs0&authSource=admin';
      final result = parseConnectionUrlInput(url);

      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'mongodb');
      expect(row.host, 'db1.example');
      expect(row.port, 27017);
      expect(row.username, 'app');
      expect(row.password, 's3cret');
      expect(row.databaseName, 'shop');
      expect(row.authSource, 'admin');
      // The whole string is kept, every seed in it.
      expect(row.connectionString, url);
    });

    test('a multi-host string with SRV or TLS still reads its options', () {
      final row = parseConnectionUrlInput(
              'mongodb://h1:27017,h2:27017/db?ssl=true&replicaSet=rs')
          .row!;
      expect(row.useSSL, isTrue);
    });

    test('returns error for invalid format', () {
      final result = parseConnectionUrlInput('not a url');
      expect(result.row, isNull);
      expect(result.error, 'Invalid URL/URI format.');
    });

    test('returns error for unsupported scheme', () {
      final result = parseConnectionUrlInput('ftp://localhost/db');
      expect(result.row, isNull);
      expect(result.error, contains('Unsupported protocol'));
    });

    test('parses postgresql URL with credentials and database', () {
      final result = parseConnectionUrlInput(
        'postgresql://alice:secret@db.example.com:5432/myapp',
      );
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'postgresql');
      expect(row.name, 'PostgreSQL: myapp');
      expect(row.host, 'db.example.com');
      expect(row.port, 5432);
      expect(row.username, 'alice');
      expect(row.password, 'secret');
      expect(row.databaseName, 'myapp');
      expect(row.connectionString,
          'postgresql://alice:secret@db.example.com:5432/myapp');
      expect(row.useSSL, false);
    });

    test('parses postgres alias scheme', () {
      final result = parseConnectionUrlInput('postgres://localhost/appdb');
      expect(result.error, isNull);
      expect(result.row!.type, 'postgresql');
      expect(result.row!.port, 5432);
      expect(result.row!.databaseName, 'appdb');
    });

    test('parses postgresql sslmode=require', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=require',
      );
      expect(result.error, isNull);
      expect(result.row!.useSSL, true);
    });

    test('parses postgresql sslmode=verify-full as SSL enabled', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=verify-full',
      );
      expect(result.error, isNull);
      expect(result.row!.useSSL, true);
    });

    test('parses postgresql sslmode=verify-ca as SSL enabled', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=verify-ca',
      );
      expect(result.error, isNull);
      expect(result.row!.useSSL, true);
    });

    test('parses postgresql sslmode=disable as SSL disabled', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=disable',
      );
      expect(result.error, isNull);
      expect(result.row!.useSSL, false);
    });

    test('returns error for postgresql sslmode=prefer', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=prefer',
      );
      expect(result.row, isNull);
      expect(result.error, contains('Unsupported sslmode'));
      expect(result.error, contains('prefer'));
    });

    test('returns error for invalid postgresql sslmode', () {
      final result = parseConnectionUrlInput(
        'postgresql://localhost/postgres?sslmode=invalid',
      );
      expect(result.row, isNull);
      expect(result.error, contains('Unsupported sslmode'));
    });

    test('parses mysql URL', () {
      final result = parseConnectionUrlInput(
        'mysql://root:p%40ss@127.0.0.1:3307/sakila',
      );
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'mysql');
      expect(row.name, 'MySQL: sakila');
      expect(row.host, '127.0.0.1');
      expect(row.port, 3307);
      expect(row.username, 'root');
      expect(row.password, 'p@ss');
      expect(row.connectionString, 'mysql://root:p%40ss@127.0.0.1:3307/sakila');
    });

    test('parses sqlite file path', () {
      final result = parseConnectionUrlInput('sqlite:///tmp/test.db');
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'sqlite');
      expect(row.host, '/tmp/test.db');
      expect(row.name, 'SQLite (test.db)');
    });

    test('parses sqlite in-memory', () {
      final result = parseConnectionUrlInput('sqlite:///:memory:');
      expect(result.error, isNull);
      expect(result.row!.host, ':memory:');
      expect(result.row!.name, 'SQLite (Memory)');
    });

    test('parses mongodb URL with authSource', () {
      final result = parseConnectionUrlInput(
        'mongodb://admin:pass@mongo.local:27017/app?authSource=admin',
      );
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'mongodb');
      expect(row.name, 'MongoDB: app');
      expect(row.authSource, 'admin');
      expect(row.connectionString, contains('mongodb://'));
    });

    test('parses mongodb+srv URL', () {
      final result = parseConnectionUrlInput(
        'mongodb+srv://user:pass@cluster.example.net/mydb',
      );
      expect(result.error, isNull);
      expect(result.row!.type, 'mongodb');
      expect(result.row!.host, 'cluster.example.net');
      expect(result.row!.databaseName, 'mydb');
    });

    test('parses redis URL', () {
      final result =
          parseConnectionUrlInput('redis://:password@localhost:6379');
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'redis');
      expect(row.name, 'Redis: localhost:6379');
      expect(row.password, 'password');
      expect(
        row.connectionString,
        'redis://:password@localhost:6379',
      );
    });

    test('uses default driver port when URI omits port', () {
      final result = parseConnectionUrlInput('postgresql://localhost/mydb');
      expect(result.error, isNull);
      expect(result.row!.port, 5432);
      expect(result.row!.name, 'PostgreSQL: mydb');
    });

    test('parses rediss URL with SSL enabled', () {
      final result = parseConnectionUrlInput('rediss://localhost');
      expect(result.error, isNull);
      expect(result.row!.type, 'redis');
      expect(result.row!.useSSL, true);
      expect(result.row!.port, 6379);
      expect(result.row!.connectionString, 'rediss://localhost');
    });

    test('keeps Redis TLS cert query params on the stored URI', () {
      const url = 'rediss://cache.example.com:6380?sslrootcert=/ca.pem';
      final result = parseConnectionUrlInput(url);
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'redis');
      expect(row.useSSL, true);
      expect(row.host, 'cache.example.com');
      expect(row.port, 6380);
      expect(row.connectionString, url);
    });

    test('password with colon is preserved', () {
      final result = parseConnectionUrlInput(
        'postgresql://user:p%3Aart@localhost/mydb',
      );
      expect(result.error, isNull);
      expect(result.row!.password, 'p:art');
    });
  });
}
