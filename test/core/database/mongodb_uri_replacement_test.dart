import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';

void main() {
  group('MongoDB URI database replacement', () {
    test('replaces database in URI without existing database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
      );
      final adminUri = conn.buildUriForDatabase('admin');
      expect(adminUri, contains('/admin'));
      expect(adminUri, contains('root:root'));
    });

    test('replaces database in URI with existing database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        database: 'mydb',
      );
      final adminUri = conn.buildUriForDatabase('admin');
      expect(adminUri, contains('/admin'));
      // Should have authSource=mydb because original db was mydb
      expect(adminUri, contains('authSource=mydb'));
    });

    test('preserves explicit authSource when replacing database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        authSource: 'admin',
      );
      final otherUri = conn.buildUriForDatabase('mydb');
      expect(otherUri, contains('/mydb'));
      expect(otherUri, contains('authSource=admin'));
    });

    test('preserves multiple query parameters when replacing database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        authSource: 'admin',
        replicaSet: 'rs0',
        useSSL: true,
      );
      final otherUri = conn.buildUriForDatabase('testdb');
      expect(otherUri, contains('/testdb'));
      expect(otherUri, contains('authSource=admin'));
      expect(otherUri, contains('replicaSet=rs0'));
      expect(otherUri, contains('ssl=true'));
    });

    test('replaces database with custom database name', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'olddb',
      );
      final newDbUri = conn.buildUriForDatabase('newdb');
      expect(newDbUri, contains('/newdb'));
      // No credentials → no authSource added
      expect(newDbUri, isNot(contains('authSource')));
    });

    test('handles URI without authentication', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      final adminUri = conn.buildUriForDatabase('admin');
      expect(adminUri, contains('/admin'));
      // No credentials → no authSource added
      expect(adminUri, isNot(contains('authSource')));
    });

    test('handles URI with custom port', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        port: 27018,
        username: 'root',
        password: 'root',
      );
      final adminUri = conn.buildUriForDatabase('admin');
      expect(adminUri, contains(':27018'));
      expect(adminUri, contains('/admin'));
    });

    test('handles connectionString URI replacement', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString:
            'mongodb://user:pass@host:27017/mydb?authSource=admin',
      );
      final otherUri = conn.buildUriForDatabase('otherdb');
      expect(otherUri, contains('/otherdb'));
      // Explicit authSource in connection string is preserved
      expect(otherUri, contains('authSource=admin'));
    });

    test('ensures no literal dollar sign appears in final URI', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
      );
      final adminUri = conn.buildUriForDatabase('admin');
      expect(adminUri, isNot(contains(r'$1')));
      expect(adminUri, isNot(contains('admin\$1')));
      expect(adminUri, isNot(contains(r'admin$1')));
      expect(adminUri, contains('/admin'));
    });

    // ─── authSource auto-injection tests ───────────────────────────────

    test('auto-adds authSource=admin when credentials present and no db', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
      );
      // Original URI has no database path → authSource should default to admin
      final uri = conn.buildUriForDatabase('testdb');
      expect(uri, contains('/testdb'));
      expect(uri, contains('authSource=admin'));
    });

    test('auto-adds authSource=origDb when credentials and db are present', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        database: 'mydb',
      );
      // Original URI has /mydb → authSource should be mydb
      final uri = conn.buildUriForDatabase('otherdb');
      expect(uri, contains('/otherdb'));
      expect(uri, contains('authSource=mydb'));
    });

    test('does not override explicit authSource', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        database: 'mydb',
        authSource: 'admin',
      );
      // Explicit authSource=admin should be preserved, NOT overridden to mydb
      final uri = conn.buildUriForDatabase('otherdb');
      expect(uri, contains('/otherdb'));
      expect(uri, contains('authSource=admin'));
    });

    test('no authSource added when no credentials', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
      );
      final uri = conn.buildUriForDatabase('testdb');
      expect(uri, contains('/testdb'));
      expect(uri, isNot(contains('authSource')));
    });
  });
}
