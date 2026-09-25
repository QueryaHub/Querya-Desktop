import 'dart:io';

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

    test('resolveMongoTlsCertificateKeyFile restricts permissions and merges cert and key', () async {
      final testDir = await Directory.systemTemp.createTemp('querya_test_input_');
      final certFile = File('${testDir.path}/test_cert.pem');
      final keyFile = File('${testDir.path}/test_key.pem');
      await certFile.writeAsString('-----BEGIN CERTIFICATE-----\nTEST_CERT\n-----END CERTIFICATE-----\n');
      await keyFile.writeAsString('-----BEGIN PRIVATE KEY-----\nTEST_KEY\n-----END PRIVATE KEY-----\n');

      final pemPath = await resolveMongoTlsCertificateKeyFile(
        clientCert: certFile.path,
        clientKey: keyFile.path,
      );

      expect(pemPath, isNotNull);
      expect(pemPath, contains(kMongoTlsTempPrefix));

      final createdFile = File(pemPath!);
      expect(await createdFile.exists(), isTrue);

      final content = await createdFile.readAsString();
      expect(content, contains('TEST_CERT'));
      expect(content, contains('TEST_KEY'));

      if (!Platform.isWindows) {
        final fileStat = createdFile.statSync();
        // Mode mask 0x1ff (0777). 0600 octal == 0x180 (384).
        expect(fileStat.mode & 0x1ff, equals(0x180));

        final dirStat = createdFile.parent.statSync();
        // 0700 octal == 0x1c0 (448).
        expect(dirStat.mode & 0x1ff, equals(0x1c0));
      }

      // Cleanup test file
      await cleanupMongoTlsTempFile(pemPath);
      expect(await createdFile.exists(), isFalse);
      expect(await createdFile.parent.exists(), isFalse);

      await testDir.delete(recursive: true);
    });

    test('cleanupMongoTlsTempFile does not delete files outside kMongoTlsTempPrefix', () async {
      final testDir = await Directory.systemTemp.createTemp('querya_other_dir_');
      final safeFile = File('${testDir.path}/important.pem');
      await safeFile.writeAsString('CRITICAL DATA');

      await cleanupMongoTlsTempFile(safeFile.path);

      expect(await safeFile.exists(), isTrue);
      expect(await testDir.exists(), isTrue);

      await testDir.delete(recursive: true);
    });

    test('cleanupStaleMongoTlsTempFiles removes orphaned temporary directories', () async {
      final orphanDir = await Directory.systemTemp.createTemp(kMongoTlsTempPrefix);
      final orphanFile = File('${orphanDir.path}/client.pem');
      await orphanFile.writeAsString('stale key');

      expect(await orphanDir.exists(), isTrue);

      await cleanupStaleMongoTlsTempFiles();

      expect(await orphanDir.exists(), isFalse);
    });

    test('buildSecurityContext returns null when paths.hasAny is false', () {
      const paths = SslCertificatePaths();
      final ctx = buildSecurityContext(paths);
      expect(ctx, isNull);
    });

    test('buildSecurityContext initializes SecurityContext with system trusted roots', () async {
      final testDir = await Directory.systemTemp.createTemp('querya_sec_ctx_');
      final certFile = File('${testDir.path}/client.crt');
      final keyFile = File('${testDir.path}/client.key');
      await certFile.writeAsString('-----BEGIN CERTIFICATE-----\nTEST_CERT\n-----END CERTIFICATE-----\n');
      await keyFile.writeAsString('-----BEGIN PRIVATE KEY-----\nTEST_KEY\n-----END PRIVATE KEY-----\n');

      final paths = SslCertificatePaths(
        clientCert: certFile.path,
        clientKey: keyFile.path,
      );
      final ctx = buildSecurityContext(paths);
      expect(ctx, isNotNull);

      await testDir.delete(recursive: true);
    });

    test('buildSecurityContext applies custom root CA certificate', () async {
      final testDir = await Directory.systemTemp.createTemp('querya_sec_ctx_root_');
      final rootFile = File('${testDir.path}/root.crt');
      await rootFile.writeAsString('-----BEGIN CERTIFICATE-----\nROOT_CA\n-----END CERTIFICATE-----\n');

      final paths = SslCertificatePaths(
        rootCert: rootFile.path,
      );
      final ctx = buildSecurityContext(paths);
      expect(ctx, isNotNull);

      await testDir.delete(recursive: true);
    });
  });
}
