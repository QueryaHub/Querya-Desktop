import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart' show SslMode;
// ignore: implementation_imports
import 'package:postgres/src/connection_string.dart' show parseConnectionString;

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
          'postgresql://localhost/postgres?sslmode=prefer',
        ),
        throwsArgumentError,
      );
    });
  });
}
