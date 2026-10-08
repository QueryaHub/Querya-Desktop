import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connection_url_parser.dart';

void main() {
  group('connection URLs', () {
    test('postgresql with user, password, database and sslmode', () {
      final r = parseConnectionUrlInput(
              'postgresql://alice:s3cret@db.example.com:6543/shop?sslmode=require')
          .row!;
      expect(r.type, 'postgresql');
      expect(r.host, 'db.example.com');
      expect(r.port, 6543);
      expect(r.username, 'alice');
      expect(r.password, 's3cret');
      expect(r.databaseName, 'shop');
      expect(r.useSSL, isTrue);
    });

    test('mysql with default port', () {
      final r = parseConnectionUrlInput('mysql://root:pw@localhost/app').row!;
      expect(r.type, 'mysql');
      expect(r.port, 3306);
      expect(r.databaseName, 'app');
    });

    test('mongodb+srv', () {
      final r = parseConnectionUrlInput(
              'mongodb+srv://u:p@cluster0.example.mongodb.net/db?retryWrites=true')
          .row!;
      expect(r.type, 'mongodb');
      expect(r.host, 'cluster0.example.mongodb.net');
      expect(r.username, 'u');
    });

    test('redis with password only', () {
      final r = parseConnectionUrlInput('redis://:topsecret@cache:6380/2').row!;
      expect(r.type, 'redis');
      expect(r.host, 'cache');
      expect(r.port, 6380);
      expect(r.password, 'topsecret');
    });

    test('rejects empty, malformed and unsupported input', () {
      expect(parseConnectionUrlInput('   ').error, isNotNull);
      expect(parseConnectionUrlInput('not a url').error, isNotNull);
      expect(parseConnectionUrlInput('ftp://host/x').error,
          contains('Unsupported protocol'));
    });
  });
}
