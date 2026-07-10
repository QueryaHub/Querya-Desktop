import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';

void main() {
  group('ssl_certificate_support', () {
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
        host: 'cache.example.com',
        port: 6380,
        useSSL: true,
        sslPaths: const SslCertificatePaths(rootCert: '/ca.pem'),
      );
      expect(uri, startsWith('rediss://'));
      expect(uri, contains('sslrootcert'));
    });

    test('buildSecurityContext returns null when no cert paths', () {
      expect(buildSecurityContext(const SslCertificatePaths()), isNull);
    });
  });
}
