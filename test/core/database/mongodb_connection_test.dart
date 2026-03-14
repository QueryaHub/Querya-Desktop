import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';

void main() {
  group('MongoConnection.buildConnectionUri', () {
    test('minimal: host only (default port)', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
      expect(conn.buildConnectionUri(), 'mongodb://localhost');
    });

    test('custom port is included when not 27017', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'db.example.com',
        port: 27018,
      );
      expect(conn.buildConnectionUri(), 'mongodb://db.example.com:27018');
    });

    test('default port 27017 is omitted', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'db.example.com',
        port: 27017,
      );
      final uri = conn.buildConnectionUri();
      expect(uri, 'mongodb://db.example.com');
      expect(uri.contains(':27017'), false);
    });

    test('username and password are included and encoded', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        username: 'admin',
        password: 'p@ss:word',
      );
      final uri = conn.buildConnectionUri();
      expect(uri, contains('admin:'));
      expect(uri, contains('@localhost'));
      // Special chars should be percent-encoded
      expect(uri, contains(Uri.encodeComponent('p@ss:word')));
    });

    test('username without password', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        username: 'admin',
      );
      final uri = conn.buildConnectionUri();
      expect(uri, startsWith('mongodb://admin@localhost'));
    });

    test('database is appended as path', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'mydb',
      );
      expect(conn.buildConnectionUri(), 'mongodb://localhost/mydb');
    });

    test('empty database is omitted from path', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: '',
      );
      expect(conn.buildConnectionUri(), 'mongodb://localhost');
    });

    test('authSource is added as query parameter', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'mydb',
        authSource: 'admin',
      );
      final uri = conn.buildConnectionUri();
      expect(uri, contains('?authSource=admin'));
    });

    test('replicaSet is added as query parameter', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        replicaSet: 'rs0',
      );
      final uri = conn.buildConnectionUri();
      expect(uri, contains('replicaSet=rs0'));
    });

    test('SSL flag is added as query parameter', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        useSSL: true,
      );
      final uri = conn.buildConnectionUri();
      expect(uri, contains('ssl=true'));
    });

    test('multiple query params are joined with &', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        database: 'db',
        authSource: 'admin',
        replicaSet: 'rs0',
        useSSL: true,
      );
      final uri = conn.buildConnectionUri();
      expect(uri, contains('authSource=admin'));
      expect(uri, contains('replicaSet=rs0'));
      expect(uri, contains('ssl=true'));
      // All params separated by &
      final queryPart = uri.split('?').last;
      expect(queryPart.split('&').length, 3);
    });

    test('full URI with all fields', () {
      final conn = MongoConnection(
        id: 1,
        name: 'prod',
        host: 'mongo.prod.io',
        port: 27018,
        username: 'root',
        password: 'secret',
        database: 'app',
        authSource: 'admin',
        replicaSet: 'rs-main',
        useSSL: true,
      );
      final uri = conn.buildConnectionUri();
      expect(uri, startsWith('mongodb://root:secret@mongo.prod.io:27018/app?'));
      expect(uri, contains('authSource=admin'));
      expect(uri, contains('replicaSet=rs-main'));
      expect(uri, contains('ssl=true'));
    });

    test('connectionString overrides everything', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        port: 27018,
        username: 'admin',
        password: 'pass',
        connectionString: 'mongodb+srv://custom-cluster.example.com/mydb',
      );
      expect(
        conn.buildConnectionUri(),
        'mongodb+srv://custom-cluster.example.com/mydb',
      );
    });

    test('empty connectionString falls back to building URI', () {
      final conn = MongoConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
        connectionString: '',
      );
      expect(conn.buildConnectionUri(), 'mongodb://localhost');
    });
  });

  group('MongoConnection initial state', () {
    test('isConnected is false before connect()', () {
      final conn = MongoConnection(id: 1, name: 'test', host: 'localhost');
      expect(conn.isConnected, false);
    });

    test('db is null before connect()', () {
      final conn = MongoConnection(id: 1, name: 'test', host: 'localhost');
      expect(conn.db, isNull);
    });
  });

  group('MongoConnection.dropDatabase', () {
    test('throws StateError when not connected', () async {
      final conn = MongoConnection(id: 1, name: 'test', host: 'localhost');
      expect(
        () => conn.dropDatabase('mydb'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected'),
        )),
      );
    });
  });
}
