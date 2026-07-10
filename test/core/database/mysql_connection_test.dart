import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';

void main() {
  group('MysqlConnection SSL URI parsing', () {
    test('enables secure when ssl certificate params are present', () {
      expect(
        MysqlConnection.connectionStringRequiresSsl(
          'mysql://user:pass@db.example.com:3306/mydb?sslrootcert=%2Fca.pem',
        ),
        isTrue,
      );
    });

    test('certificate params enable secure even when ssl-mode=disable', () {
      expect(
        MysqlConnection.connectionStringRequiresSsl(
          'mysql://localhost/db?ssl-mode=disable&sslrootcert=%2Fca.pem',
          fallbackSsl: true,
        ),
        isTrue,
      );
    });
  });

  group('replaceDatabaseInMysqlConnectionString', () {
    test('replaces path segment', () {
      expect(
        replaceDatabaseInMysqlConnectionString(
          'mysql://u:p@h:3306/olddb',
          'newdb',
        ),
        'mysql://u:p@h:3306/newdb',
      );
    });

    test('replaces database query param', () {
      expect(
        replaceDatabaseInMysqlConnectionString(
          'mysql://h:3306/?database=old',
          'new',
        ),
        contains('database=new'),
      );
    });

    test('throws on wrong scheme', () {
      expect(
        () => replaceDatabaseInMysqlConnectionString('postgres://h/db', 'x'),
        throwsArgumentError,
      );
    });
  });

  group('MysqlConnection.quoteIdentifier', () {
    test('escapes backticks', () {
      expect(
        MysqlConnection.quoteIdentifier('a`b'),
        '`a``b`',
      );
    });
  });

  group('MysqlConnection when not connected', () {
    late MysqlConnection conn;

    setUp(() {
      conn = MysqlConnection(
        id: 1,
        name: 'test',
        host: 'localhost',
      );
    });

    test('execute throws StateError', () {
      expect(
        () => conn.execute('SELECT 1'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('listDatabases throws StateError', () {
      expect(
        () => conn.listDatabases(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('listViews throws StateError', () {
      expect(
        () => conn.listViews(schema: 'db'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('listColumnNames throws StateError', () {
      expect(
        () => conn.listColumnNames(database: 'db', table: 'tbl'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('listTables throws StateError', () {
      expect(
        () => conn.listTables(schema: 'db'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('serverVersion throws StateError', () {
      expect(
        () => conn.serverVersion(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });

    test('serverStats throws StateError', () {
      expect(
        () => conn.serverStats(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Not connected to MySQL'),
        )),
      );
    });
  });
}
