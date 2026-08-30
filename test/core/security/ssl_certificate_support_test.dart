import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';

void main() {
  group('ssl_certificate_support (core)', () {
    test('extracts and applies Querya SSL params', () {
      const paths = SslCertificatePaths(
        rootCert: '/ca.pem',
        clientCert: '/client.crt',
        clientKey: '/client.key',
      );
      final uri = applySslCertificatePaths(
        Uri.parse('mongodb://localhost:27017/app'),
        paths,
      );
      expect(uri.queryParameters[kSslRootCertParam], '/ca.pem');
      expect(uri.queryParameters[kSslCertParam], '/client.crt');
      expect(uri.queryParameters[kSslKeyParam], '/client.key');
      final extracted = extractSslCertificatePaths(uri);
      expect(extracted.rootCert, '/ca.pem');
      expect(extracted.clientCert, '/client.crt');
      expect(extracted.clientKey, '/client.key');
    });

    test('buildRedisConnectionUri uses rediss scheme when SSL enabled', () {
      final uri = buildRedisConnectionUri(
        host: '127.0.0.1',
        port: 6379,
        useSSL: true,
      );
      expect(uri, startsWith('rediss://127.0.0.1:6379'));
    });

    test('translateQueryaSslParamsForMongo maps params to mongo_dart format', () {
      final input = Uri.parse(
        'mongodb://localhost:27017/app?sslrootcert=/ca.pem&sslcert=/client.crt&sslkey=/client.key',
      );
      final translated = translateQueryaSslParamsForMongo(input);
      expect(translated.queryParameters['tlsCAFile'], '/ca.pem');
      expect(translated.queryParameters['tlsCertificateKeyFile'], '/client.crt');
      expect(translated.queryParameters['sslkey'], '/client.key');
      expect(translated.queryParameters.containsKey('sslrootcert'), isFalse);
      expect(translated.queryParameters.containsKey('sslcert'), isFalse);
    });
  });
}
