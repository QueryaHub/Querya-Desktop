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
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://root:root@127.0.0.1');
      
      // Simulate the replacement logic used in listDatabases
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, 'mongodb://root:root@127.0.0.1/admin');
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
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://root:root@127.0.0.1/mydb');
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, 'mongodb://root:root@127.0.0.1/admin');
    });

    test('preserves query parameters when replacing database', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
        authSource: 'admin',
      );
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, contains('?authSource=admin'));
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, contains('/admin'));
      expect(adminUri, contains('?authSource=admin'));
      expect(adminUri, 'mongodb://root:root@127.0.0.1/admin?authSource=admin');
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
      final baseUri = conn.buildConnectionUri();
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, contains('/admin'));
      expect(adminUri, contains('authSource=admin'));
      expect(adminUri, contains('replicaSet=rs0'));
      expect(adminUri, contains('ssl=true'));
    });

    test('replaces database with custom database name', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'olddb',
      );
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://localhost/olddb');
      
      // Simulate the replacement logic used in listCollections
      final uri = Uri.parse(baseUri);
      final newDbUri = uri.replace(path: '/newdb').toString();
      expect(newDbUri, 'mongodb://localhost/newdb');
    });

    test('handles URI without authentication', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://localhost');
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, 'mongodb://localhost/admin');
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
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://root:root@127.0.0.1:27018');
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, 'mongodb://root:root@127.0.0.1:27018/admin');
    });

    test('handles connectionString URI replacement', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString: 'mongodb://user:pass@host:27017/mydb?authSource=admin',
      );
      final baseUri = conn.buildConnectionUri();
      expect(baseUri, 'mongodb://user:pass@host:27017/mydb?authSource=admin');
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      expect(adminUri, 'mongodb://user:pass@host:27017/admin?authSource=admin');
    });

    test('ensures no literal dollar sign appears in final URI', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: '127.0.0.1',
        username: 'root',
        password: 'root',
      );
      final baseUri = conn.buildConnectionUri();
      
      // Simulate the replacement logic
      final uri = Uri.parse(baseUri);
      final adminUri = uri.replace(path: '/admin').toString();
      
      // Critical: ensure no literal $1 appears (the bug we fixed)
      expect(adminUri, isNot(contains(r'$1')));
      expect(adminUri, isNot(contains('admin\$1')));
      expect(adminUri, isNot(contains(r'admin$1')));
      expect(adminUri, contains('/admin'));
    });
  });
}
