import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';

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

    test('ssl-mode=prefer enables TLS even when fallback is off', () {
      expect(
        MysqlConnection.connectionStringRequiresSsl(
          'mysql://localhost/db?ssl-mode=prefer',
          fallbackSsl: false,
        ),
        isTrue,
      );
      expect(
        MysqlConnection.sslModeFromConnectionString(
          'mysql://localhost/db?ssl-mode=prefer',
          fallbackSsl: false,
        ),
        MysqlSslMode.encrypt,
      );
    });

    test('ssl-mode=require enables TLS', () {
      expect(
        MysqlConnection.connectionStringRequiresSsl(
          'mysql://localhost/db?ssl-mode=require',
          fallbackSsl: false,
        ),
        isTrue,
      );
      expect(
        MysqlConnection.sslModeFromConnectionString(
          'mysql://localhost/db?ssl-mode=require',
        ),
        MysqlSslMode.encrypt,
      );
    });

    test('ssl-mode=disable stays off without cert params', () {
      expect(
        MysqlConnection.connectionStringRequiresSsl(
          'mysql://localhost/db?ssl-mode=disable',
          fallbackSsl: true,
        ),
        isFalse,
      );
    });

    test('ssl-mode=verify_identity verifies CA and hostname', () {
      expect(
        MysqlConnection.sslModeFromConnectionString(
          'mysql://db.example.com/db?ssl-mode=verify_identity&sslrootcert=%2Fca.pem',
        ),
        MysqlSslMode.verifyIdentity,
      );
      expect(
        MysqlConnection.sslModeFromConnectionString(
          'mysql://db.example.com/db?ssl-mode=verify-full&sslrootcert=%2Fca.pem',
        ),
        MysqlSslMode.verifyIdentity,
      );
    });

    test('ssl-mode=verify_ca requires sslrootcert', () {
      expect(
        MysqlConnection.sslModeFromConnectionString(
          'mysql://localhost/db?ssl-mode=verify_ca&sslrootcert=%2Fca.pem',
        ),
        MysqlSslMode.verifyCa,
      );
      expect(
        () => validateMysqlSslMode(
          MysqlSslMode.verifyCa,
          const SslCertificatePaths(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('sslrootcert'),
          ),
        ),
      );
      expect(
        () => validateMysqlSslMode(
          MysqlSslMode.verifyIdentity,
          const SslCertificatePaths(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => validateMysqlSslMode(
          MysqlSslMode.verifyCa,
          const SslCertificatePaths(rootCert: '/ca.pem'),
        ),
        returnsNormally,
      );
    });

    test('connect fails closed on verify_ca without sslrootcert', () async {
      final conn = MysqlConnection(
        id: 0,
        name: 't',
        host: 'localhost',
        connectionString: 'mysql://u:p@example.com/db?ssl-mode=verify_ca',
      );
      await expectLater(conn.connect(), throwsA(isA<ArgumentError>()));
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

  group('MysqlConnection.sessionTransactionAccessModeSql', () {
    test(
        'documents SET SESSION TRANSACTION (not default_transaction_read_only)',
        () {
      expect(
        MysqlConnection.sessionTransactionAccessModeSql(true),
        'SET SESSION TRANSACTION READ ONLY',
      );
      expect(
        MysqlConnection.sessionTransactionAccessModeSql(false),
        'SET SESSION TRANSACTION READ WRITE',
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
