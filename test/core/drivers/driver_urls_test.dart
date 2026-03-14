import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/drivers/driver_urls.dart';
import 'package:querya_desktop/core/drivers/driver_storage.dart';

void main() {
  group('driver_urls constants', () {
    test('postgresqlDriverUrl is valid HTTPS URL', () {
      expect(postgresqlDriverUrl, startsWith('https://'));
      expect(Uri.tryParse(postgresqlDriverUrl), isNotNull);
    });

    test('postgresqlJarFileName ends with .jar', () {
      expect(postgresqlJarFileName, endsWith('.jar'));
      expect(postgresqlJarFileName, contains('postgresql'));
    });
  });

  group('DownloadableDriver extension', () {
    test('postgresql url matches constant', () {
      expect(DownloadableDriver.postgresql.url, postgresqlDriverUrl);
    });

    test('postgresql jarFileName matches constant', () {
      expect(DownloadableDriver.postgresql.jarFileName, postgresqlJarFileName);
    });

    test('all enum values have url and jarFileName', () {
      for (final d in DownloadableDriver.values) {
        expect(d.url, isNotEmpty);
        expect(d.jarFileName, isNotEmpty);
        expect(d.jarFileName, endsWith('.jar'));
      }
    });
  });

  group('DriverDownloadException', () {
    test('stores message and toString returns it', () {
      final ex = DriverDownloadException('HTTP 404');
      expect(ex.message, 'HTTP 404');
      expect(ex.toString(), 'HTTP 404');
    });
  });
}
