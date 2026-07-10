import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/github_releases_client.dart';

void main() {
  group('parseGitHubRelease', () {
    test('maps tag, date, changelog, assets, and checksums URL', () {
      final manifest = parseGitHubRelease({
        'tag_name': 'v0.5.0',
        'published_at': '2026-07-10T12:00:00Z',
        'body': '## Highlights\n- Auto-updater core',
        'assets': [
          {
            'name': 'Querya-Desktop-0.5.0-linux.zip',
            'browser_download_url':
                'https://github.com/example/Querya-Desktop-0.5.0-linux.zip',
            'size': 123456,
          },
          {
            'name': 'SHA256SUMS.txt',
            'browser_download_url':
                'https://github.com/example/SHA256SUMS.txt',
            'size': 256,
          },
        ],
      });

      expect(manifest.version, '0.5.0');
      expect(manifest.releaseDate, DateTime.parse('2026-07-10T12:00:00Z'));
      expect(manifest.changelog, contains('Auto-updater core'));
      expect(manifest.assets, hasLength(2));
      expect(
        manifest.checksumsUrl,
        'https://github.com/example/SHA256SUMS.txt',
      );
      expect(
        manifest.assetNamed('Querya-Desktop-0.5.0-linux.zip')?.sizeBytes,
        123456,
      );
    });

    test('throws when tag_name is missing', () {
      expect(
        () => parseGitHubRelease({'body': 'x'}),
        throwsA(isA<GitHubReleasesException>()),
      );
    });
  });
}
