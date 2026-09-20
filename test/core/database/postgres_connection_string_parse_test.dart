import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' show SslMode;
// ignore: implementation_imports
import 'package:postgres/src/connection_string.dart' show parseConnectionString;
import 'package:querya_desktop/core/database/postgres_connection.dart';

/// Ensures libpq-style URI params match what we document for [PostgresConnection.connect].
void main() {
  group('parseConnectionString (postgres package)', () {
    test('sslmode=require maps to SslMode.require', () {
      final p = parseConnectionString(
        'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
      );
      expect(p.sslMode, SslMode.require);
    });

    test('sslmode=disable maps to SslMode.disable', () {
      final p = parseConnectionString(
        'postgresql://localhost/postgres?sslmode=disable',
      );
      expect(p.sslMode, SslMode.disable);
    });

    test('sslmode=verify-full maps to SslMode.verifyFull', () {
      final p = parseConnectionString(
        'postgresql://localhost/postgres?sslmode=verify-full',
      );
      expect(p.sslMode, SslMode.verifyFull);
    });

    test('sslmode=verify-ca maps to SslMode.verifyFull', () {
      final p = parseConnectionString(
        'postgresql://localhost/postgres?sslmode=verify-ca',
      );
      expect(p.sslMode, SslMode.verifyFull);
    });

    test('omitted sslmode yields null (caller may merge with useSSL)', () {
      final p = parseConnectionString('postgresql://localhost/postgres');
      expect(p.sslMode, isNull);
    });

    test('query_timeout sets duration in seconds', () {
      final p = parseConnectionString(
        'postgresql://localhost/postgres?query_timeout=120',
      );
      expect(p.queryTimeout, const Duration(seconds: 120));
    });

    test('connect_timeout sets duration in seconds', () {
      final p = parseConnectionString(
        'postgresql://localhost/postgres?connect_timeout=15',
      );
      expect(p.connectTimeout, const Duration(seconds: 15));
    });

    test('invalid sslmode throws', () {
      expect(
        () => parseConnectionString(
          'postgresql://localhost/postgres?sslmode=invalid',
        ),
        throwsArgumentError,
      );
    });
  });

  group('postgresResolveSslMode', () {
    test('URI sslmode is source of truth', () {
      expect(
        postgresResolveSslMode(
          uriSslMode: SslMode.require,
          encrypt: true,
          hasRootCert: true,
        ),
        SslMode.require,
      );
      expect(
        postgresResolveSslMode(
          uriSslMode: SslMode.verifyFull,
          encrypt: false,
          hasRootCert: false,
        ),
        SslMode.verifyFull,
      );
    });

    test('host/port SSL without CA is require (encrypt only)', () {
      expect(
        postgresResolveSslMode(encrypt: true, hasRootCert: false),
        SslMode.require,
      );
    });

    test('host/port with Root CA is verifyFull', () {
      expect(
        postgresResolveSslMode(encrypt: true, hasRootCert: true),
        SslMode.verifyFull,
      );
      expect(
        postgresResolveSslMode(encrypt: false, hasRootCert: true),
        SslMode.verifyFull,
      );
    });

    test('no SSL and no CA is disable', () {
      expect(
        postgresResolveSslMode(encrypt: false, hasRootCert: false),
        SslMode.disable,
      );
    });
  });

  group('postgresReltuplesEstimate', () {
    test('rounds planner floats and treats unanalyzed as unknown', () {
      expect(postgresReltuplesEstimate(200.4), 200);
      expect(postgresReltuplesEstimate(199.6), 200);
      expect(postgresReltuplesEstimate(0), 0);
      expect(postgresReltuplesEstimate(-1), isNull);
      expect(postgresReltuplesEstimate(null), isNull);
    });
  });
}
