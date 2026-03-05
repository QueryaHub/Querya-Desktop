import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';

void main() {
  group('MongoConnectionData.isValid', () {
    test('valid when name and host are provided', () {
      final data = MongoConnectionData(
        name: 'My Server',
        host: 'localhost',
      );
      expect(data.isValid, true);
    });

    test('invalid when name is empty', () {
      final data = MongoConnectionData(
        name: '',
        host: 'localhost',
      );
      expect(data.isValid, false);
    });

    test('invalid when host is empty', () {
      final data = MongoConnectionData(
        name: 'Server',
        host: '',
      );
      expect(data.isValid, false);
    });

    test('invalid when both name and host are empty', () {
      final data = MongoConnectionData(
        name: '',
        host: '',
      );
      expect(data.isValid, false);
    });

    test('invalid when name is only whitespace', () {
      final data = MongoConnectionData(
        name: '   ',
        host: 'localhost',
      );
      expect(data.isValid, false);
    });

    test('invalid when host is only whitespace', () {
      final data = MongoConnectionData(
        name: 'Server',
        host: '   ',
      );
      expect(data.isValid, false);
    });

    test('valid with connection string (overrides name+host)', () {
      final data = MongoConnectionData(
        name: '',
        host: '',
        connectionString: 'mongodb://localhost:27017/db',
      );
      expect(data.isValid, true);
    });

    test('invalid with empty connection string and empty name', () {
      final data = MongoConnectionData(
        name: '',
        host: 'localhost',
        connectionString: '',
      );
      expect(data.isValid, false);
    });

    test('valid with connection string ignoring name and host', () {
      final data = MongoConnectionData(
        name: '',
        host: '',
        connectionString: 'mongodb+srv://cluster.example.com',
      );
      expect(data.isValid, true);
    });
  });

  group('MongoConnectionData defaults', () {
    test('default values are correct', () {
      final data = MongoConnectionData();
      expect(data.name, '');
      expect(data.host, 'localhost');
      expect(data.port, 27017);
      expect(data.username, isNull);
      expect(data.password, isNull);
      expect(data.database, isNull);
      expect(data.authSource, isNull);
      expect(data.useSSL, false);
      expect(data.connectionString, isNull);
    });

    test('custom values are stored', () {
      final data = MongoConnectionData(
        name: 'Prod',
        host: 'db.prod.io',
        port: 27018,
        username: 'admin',
        password: 'pass',
        database: 'appdb',
        authSource: 'admin',
        useSSL: true,
        connectionString: 'mongodb://custom',
      );
      expect(data.name, 'Prod');
      expect(data.host, 'db.prod.io');
      expect(data.port, 27018);
      expect(data.username, 'admin');
      expect(data.password, 'pass');
      expect(data.database, 'appdb');
      expect(data.authSource, 'admin');
      expect(data.useSSL, true);
      expect(data.connectionString, 'mongodb://custom');
    });
  });
}
