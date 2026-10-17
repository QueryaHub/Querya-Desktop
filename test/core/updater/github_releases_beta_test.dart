import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:querya_desktop/core/updater/github_releases_client.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';

Map<String, Object?> _release(String tag, {bool draft = false}) => {
      'tag_name': tag,
      'draft': draft,
      'published_at': '2026-10-01T00:00:00Z',
      'body': '',
      'assets': const <Object>[],
    };

// The Beta channel reads `/releases`, which is ordered by creation date; the
// answer must be the highest version, whatever the order (#1493).
void main() {
  group('pickNewestRelease', () {
    String newest(List<Map<String, Object?>> list) =>
        pickNewestRelease(list).version;

    test('a hotfix published after a beta does not hide the newer beta', () {
      expect(
        newest([
          _release('0.4.20'),
          _release('0.5.0-beta.2'),
          _release('0.5.0-beta.1'),
        ]),
        '0.5.0-beta.2',
      );
    });

    test('a stable release outranks its own beta', () {
      expect(newest([_release('0.5.0-beta.1'), _release('0.5.0')]), '0.5.0');
      expect(newest([_release('0.5.0'), _release('0.5.0-beta.3')]), '0.5.0');
    });

    test('pre-release numbers compare as numbers: beta.10 is above beta.2', () {
      expect(
        newest([_release('0.5.0-beta.2'), _release('0.5.0-beta.10')]),
        '0.5.0-beta.10',
      );
    });

    test('a leading v is ignored', () {
      expect(newest([_release('v0.4.19'), _release('v0.4.21')]), '0.4.21');
    });

    test('drafts and tags that are not versions are skipped', () {
      expect(
        newest([
          _release('0.9.0', draft: true),
          _release('nightly'),
          _release('0.4.19'),
        ]),
        '0.4.19',
      );
    });

    test('nothing usable is "No published releases found"', () {
      expect(
        () => pickNewestRelease([_release('0.9.0', draft: true), _release('x')]),
        throwsA(isA<GitHubReleasesException>().having(
          (e) => e.message,
          'message',
          'No published releases found',
        )),
      );
      expect(() => pickNewestRelease(const []),
          throwsA(isA<GitHubReleasesException>()));
    });
  });

  group('GitHubReleasesClient.fetchLatest', () {
    GitHubReleasesClient clientFor(List<Map<String, Object?>> releases) =>
        GitHubReleasesClient(
          httpClient: MockClient((request) async {
            expect(request.url.toString(), kGitHubReleasesListUrl);
            return http.Response(jsonEncode(releases), 200);
          }),
        );

    test('the Beta channel returns the highest version of the list', () async {
      final manifest = await clientFor([
        _release('0.4.20'),
        _release('0.5.0-beta.2'),
      ]).fetchLatest(channel: UpdateChannel.dev);
      expect(manifest.version, '0.5.0-beta.2');
    });
  });
}
