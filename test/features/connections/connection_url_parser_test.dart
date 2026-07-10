import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connection_url_parser.dart';

void main() {
  group('parseConnectionUrlInput', () {
    test('returns error for empty input', () {
      final result = parseConnectionUrlInput('  ');
      expect(result.row, isNull);
      expect(result.error, 'URL/URI is required.');
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
      expect(row.connectionString, 'postgresql://alice:secret@db.example.com:5432/myapp');
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
      final result = parseConnectionUrlInput('redis://:password@localhost:6379');
      expect(result.error, isNull);
      final row = result.row!;
      expect(row.type, 'redis');
      expect(row.name, 'Redis: localhost:6379');
      expect(row.password, 'password');
      expect(row.connectionString, isNull);
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
