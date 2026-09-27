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

    const validCertPem = '''-----BEGIN CERTIFICATE-----
MIIDCTCCAfGgAwIBAgIUaf9MPYX80yFJlevK8mydpFPRUSUwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDkyNTA3MjQzMVoXDTI3MDky
NTA3MjQzMVowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEAsqAeJVJ6+kJnPFp9Bzjm8pjxTLOSJ0DvkJ+BsHF/rW0H
hDU5rFY6xgMUyM4Y2bXBa+BVSpnhzVEr6zOr5hebDq7fbTrtL3YSiCtxEVqlqjZg
njHl9/A90162YvbR1FOOshYGcARbP/hWsuJUNJRzX9Loqk+DDGHG1HdYF8ra81aQ
naWiImvXGWD6oQYG0HlSgzhMsFJrYXxc04z/PA8MTKiKtiEhNttyrexp7MEL7zMu
xD11Nwmxsi77p1IJ88ijri73ck9Rogz0LwhY/SUM8JAN8bCX+HaHcwH15SrXY9Yy
ec6gKXM4U1Jr0ZQ3An1eUNVg4SWpLbbn9oxrBms2vwIDAQABo1MwUTAdBgNVHQ4E
FgQUz0yjkIl5wxdfbvjBtmOTokQgCM0wHwYDVR0jBBgwFoAUz0yjkIl5wxdfbvjB
tmOTokQgCM0wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAlt5X
t/a9GmtPaw8cGZ4Y/xGT3aFoAQ+TBHLY+pDRR7erIEmWhwqf33uW+67DKW9jldeN
NofYn0sO4b4pshqBxhhcbnOWW+z37+njqdd/xUZ30siSDAf4FhwnaVNdPhAjo5uP
+UQ8dpr4NH9RKcNf0PDUmO1WCgjTIa1/XMqOQ5e4qfz+bbsQNVlAAXbXP6jJ3XmY
opXp+c8iH9E/Uv/wr9P5biqY9BzcrLciA08kUZBl4gF9dgBqsUQeSOnXOMeHNY2j
Bq/8MW8ajmUnR+/RHEOQNdVPSpXfeiyhHC1yC0RClPs0jYaEMboczJ/Z0AbagDuv
3dcW4xSuDp00JS6xLg==
-----END CERTIFICATE-----''';

    const validKeyPem = '''-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCyoB4lUnr6Qmc8
Wn0HOObymPFMs5InQO+Qn4GwcX+tbQeENTmsVjrGAxTIzhjZtcFr4FVKmeHNUSvr
M6vmF5sOrt9tOu0vdhKIK3ERWqWqNmCeMeX38D3TXrZi9tHUU46yFgZwBFs/+Fay
4lQ0lHNf0uiqT4MMYcbUd1gXytrzVpCdpaIia9cZYPqhBgbQeVKDOEywUmthfFzT
jP88DwxMqIq2ISE223Kt7GnswQvvMy7EPXU3CbGyLvunUgnzyKOuLvdyT1GiDPQv
CFj9JQzwkA3xsJf4dodzAfXlKtdj1jJ5zqApczhTUmvRlDcCfV5Q1WDhJakttuf2
jGsGaza/AgMBAAECggEAAl3Kz02fyHMa5bq3uuHV4o67bVcz8/h1wbrMX6490UWQ
bP+88O4IXycJJ4Zwlo3EXP/+vvtVC9Lr92JayUbG7JgWVl7BZ8rqJTirQJT16nT+
9kBoQypBGtqIt5gzoLZlz+gEXNDTGhMQg4rhCyD+VgIlo1tkco2d6OvyZppKTUWp
kXmRE3I4BR7hinTGcKGq2b5GHb408ZumCgjgZfwtGHdqhQzoRw/j3GZV4r+7p/Y8
ZmBtonapsHNicgGn0NK488hkTIk2G8kzww5Xuo4UFr4ZEmy6dGLCGOGDzwTBTBho
uoiSapd9Xi/F4UBH9sjMn6UJBn/3AzUD6tCl2WA0HQKBgQDd6Q+zK2p5mSZZSaGb
RyGXk0y9fGurQ02sB/fOWEjzia85LrkmdC7BZykdgwJ2iOJaYYXTpgpMqgf1nCRq
S8WbC5ik0NclE7SYnYnTc5gW6QjU1cHX0QOzjzu58DPUc2ZBu2sQlV5Ffwhzsr+I
o2uBxDlSavHexY2GPnUMmMmiCwKBgQDOENC+HrQEX+3bOUQELJQDTx9j+uChNmAp
jHynO1iDGaM+uyd6NhqtGuXBPHhEUcVMFfp/VOKfO5q+ckO6LcLHXVduQ21+1+JA
vo47z5K14ynZkYN1NJdaXgCKBW/k+JG7hId2zeFxzEPiSzj+7rxGRbvPE/RJhjU5
P0kb/nRCnQKBgECsV+MD2DgwJjkHeI3koSmnyEnBJS/4oX5tpA8DM9+mVOb5cwR9
/9Jl2lm7gNBC/JUSrwoL7hyBwWgXZZWFF8YkDwyZwNoRcCS6ZRy3J7AlomlFEwVu
6QE/0UxTcQeNylOF56IhpiPi7feqNKAB4KclJP+cI3mlYaWqNjrBnKIZAoGAXVWY
dsSJXQHmRkll2U4nrGgGG87iN6LdY3RScZybtqXCHwO+GcivxIBOWHv/LVKsPo4l
686S5vSkXmZ67rUTaCGLHFJGIhG+VPz6h3S5StEdf4I9PLUZaMDzFZDo4ZkEyR56
DQGrf1O526GeqzmO5XVoX572Iuc67DcR8jAKkLECgYAkPigDPHZ5d5kFcS/YEya2
Rew/doODqiEstN7GO89KNLi1dDbuUOljs8ii2WY71XE7KQFBN2Fv4qVxdl3AfgnJ
kbu2ounmhZaVEbvHOw1zCcCYo25vBxcAa8zoBX2z2CAfN7/vkdOHKVDPr+wSnwaS
eQ6/4mA+Eqf0w+s+IOflBw==
-----END PRIVATE KEY-----''';

    test('buildSecurityContext initializes SecurityContext with system trusted roots', () async {
      final testDir = await Directory.systemTemp.createTemp('querya_sec_ctx_');
      final certFile = File('${testDir.path}/client.crt');
      final keyFile = File('${testDir.path}/client.key');
      await certFile.writeAsString(validCertPem);
      await keyFile.writeAsString(validKeyPem);

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
      await rootFile.writeAsString(validCertPem);

      final paths = SslCertificatePaths(
        rootCert: rootFile.path,
      );
      final ctx = buildSecurityContext(paths);
      expect(ctx, isNotNull);

      await testDir.delete(recursive: true);
    });
  });
}
