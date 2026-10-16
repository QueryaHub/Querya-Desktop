import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/market/static_registry_repository.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _asset = 'https://github.com/acme/ext/releases/download/v1.0.0/ext.zip';

Map<String, Object?> _entry(
  String id, {
  String type = 'theme',
  String url = _asset,
  Object? sha = _sha,
  String engines = '>=0.4.19',
  bool yanked = false,
  List<String> tags = const [],
}) =>
    {
      'id': id,
      'name': 'Name of $id',
      'version': '1.0.0',
      'publisher': 'Acme',
      'type': type,
      'engines': {'querya_desktop': engines},
      'downloadUrl': url,
      'sha256': sha,
      'tags': tags,
      if (yanked) 'yanked': true,
    };

String _index(List<Map<String, Object?>> entries, {Object schema = 1}) =>
    jsonEncode({'schema': schema, 'extensions': entries});

void main() {
  group('StaticRegistryRepository.parseIndex', () {
    List<String> ids(Object decoded, {String host = '0.5.0'}) => [
          for (final m
              in StaticRegistryRepository.parseIndex(decoded, hostVersion: host))
            m.id,
        ];

    test('keeps installable entries and drops the rest', () {
      final decoded = {
        'schema': 1,
        'extensions': [
          _entry('ok.one'),
          _entry('bad.yanked', yanked: true),
          _entry('bad.host', url: 'https://example.com/ext.zip'),
          _entry('bad.archive', url: 'https://github.com/acme/ext/archive/main.zip'),
          _entry('bad.nosha', sha: ''),
          _entry('bad.nullsha', sha: null),
          _entry('bad.engines', engines: '>=9.0.0'),
          {'name': 'no id at all'},
          'not an object',
          _entry('ok.two'),
        ],
      };
      expect(ids(decoded), ['ok.one', 'ok.two']);
    });

    test('hides extensions the running Querya is too old for', () {
      final decoded = {
        'schema': 1,
        'extensions': [_entry('new.only', engines: '>=0.5.0'), _entry('any')],
      };
      expect(ids(decoded, host: '0.4.19'), ['any']);
      expect(ids(decoded, host: '0.5.0'), ['new.only', 'any']);
    });

    test('keeps an engines range it cannot read (the host does not enforce it)', () {
      expect(ids({'schema': 1, 'extensions': [_entry('x', engines: '*')]}), ['x']);
    });

    test('refuses an index of another format or shape', () {
      expect(() => StaticRegistryRepository.parseIndex({'schema': 2, 'extensions': []}, hostVersion: '0.5.0'),
          throwsA(isA<MarketplaceException>()));
      expect(() => StaticRegistryRepository.parseIndex([], hostVersion: '0.5.0'),
          throwsA(isA<MarketplaceException>()));
    });
  });

  group('StaticRegistryRepository.isReleaseAssetUrl', () {
    bool ok(String u) => StaticRegistryRepository.isReleaseAssetUrl(Uri.parse(u));

    test('accepts only a GitHub release asset over https', () {
      expect(ok(_asset), isTrue);
      expect(ok('http://github.com/acme/ext/releases/download/v1/ext.zip'), isFalse);
      expect(ok('https://evil.com/acme/ext/releases/download/v1/ext.zip'), isFalse);
      expect(ok('https://github.com.evil.com/acme/ext/releases/download/v1/ext.zip'), isFalse);
      expect(ok('https://github.com/acme/ext/archive/refs/heads/main.zip'), isFalse);
      expect(ok('https://github.com/acme/ext/releases/latest'), isFalse);
      expect(ok('https://github.com/acme/ext/releases/download/v1/'), isFalse);
      expect(ok('https://github.com/acme/ext/releases/download/v1/a/b.zip'), isFalse);
    });
  });

  group('StaticRegistryRepository', () {
    var requests = 0;
    var now = DateTime(2026, 10, 16, 12);

    StaticRegistryRepository repo(
      http.Client client, {
      String host = '0.5.0',
    }) =>
        StaticRegistryRepository(
          hostVersion: host,
          client: client,
          now: () => now,
        );

    setUp(() {
      requests = 0;
      now = DateTime(2026, 10, 16, 12);
    });

    MockClient indexClient(List<Map<String, Object?>> entries) =>
        MockClient((request) async {
          requests++;
          expect(request.url.toString(), StaticRegistryRepository.defaultIndexUrl);
          return http.Response(_index(entries), 200);
        });

    test('lists and filters by type', () async {
      final r = repo(indexClient([
        _entry('a.theme'),
        _entry('b.driver', type: 'databaseDriver'),
      ]));
      expect((await r.getTrending()).map((m) => m.id), ['a.theme', 'b.driver']);
      expect((await r.getTrending(type: ExtensionType.theme)).map((m) => m.id), ['a.theme']);
    });

    test('searches name, id, publisher and tags', () async {
      final r = repo(indexClient([
        _entry('a.one', tags: ['nord']),
        _entry('b.two'),
      ]));
      expect((await r.search('NORD')).map((m) => m.id), ['a.one']);
      expect((await r.search('b.two')).map((m) => m.id), ['b.two']);
      expect((await r.search('acme')).length, 2);
      expect(await r.search('nothing like it'), isEmpty);
      expect((await r.search('  ')).length, 2);
    });

    test('caches the index for the TTL and refetches after it', () async {
      final r = repo(indexClient([_entry('a')]));
      await r.getTrending();
      await r.search('a');
      expect(requests, 1);
      now = now.add(const Duration(minutes: 11));
      await r.getTrending();
      expect(requests, 2);
    });

    test('serves the last good copy when a refresh fails', () async {
      var fail = false;
      final r = repo(MockClient((request) async {
        if (fail) return http.Response('down', 503);
        return http.Response(_index([_entry('a')]), 200);
      }));
      expect(await r.getTrending(), hasLength(1));
      fail = true;
      now = now.add(const Duration(hours: 1));
      expect(await r.getTrending(), hasLength(1));
    });

    test('reports an unreachable registry when there is no copy yet', () async {
      final r = repo(MockClient((request) async => http.Response('nope', 404)));
      expect(
        r.getTrending(),
        throwsA(isA<MarketplaceException>()
            .having((e) => e.message, 'message', contains('HTTP 404'))),
      );
    });

    test('download refuses anything but a release asset', () {
      final r = repo(indexClient([]));
      expect(() => r.download('https://example.com/ext.zip'),
          throwsA(isA<MarketplaceException>()));
      expect(() => r.download('https://github.com/acme/ext/archive/main.zip'),
          throwsA(isA<MarketplaceException>()));
    });

    group('install', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('querya_static_registry_');
        ExtensionPaths.mockExtensionsDirectory = tempDir;
        await LocalExtensionRegistry.instance.reload();
      });

      tearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        ExtensionPaths.mockExtensionsDirectory = null;
      });

      test('downloads the release asset, checks its hash and unpacks it', () async {
        final archive = Archive()
          ..addFile(ArchiveFile('theme.json', 2, utf8.encode('{}')));
        final zip = ZipEncoder().encode(archive);
        final sha = sha256.convert(zip).toString();

        final r = repo(MockClient((request) async {
          if (request.url.toString() == StaticRegistryRepository.defaultIndexUrl) {
            return http.Response(_index([_entry('acme.theme', sha: sha)]), 200);
          }
          expect(request.url.toString(), _asset);
          return http.Response.bytes(zip, 200);
        }));

        final entry = (await r.getTrending()).single;
        await r.install(entry);

        expect(File(p.join(tempDir.path, 'acme.theme', 'theme.json')).existsSync(), isTrue);
      });

      test('refuses an archive whose hash is not the one in the index', () async {
        final archive = Archive()
          ..addFile(ArchiveFile('theme.json', 2, utf8.encode('{}')));
        final zip = ZipEncoder().encode(archive);

        final r = repo(MockClient((request) async {
          if (request.url.toString() == StaticRegistryRepository.defaultIndexUrl) {
            return http.Response(_index([_entry('acme.theme')]), 200);
          }
          return http.Response.bytes(zip, 200);
        }));

        final entry = (await r.getTrending()).single;
        expect(
          () => r.install(entry),
          throwsA(isA<MarketplaceException>()
              .having((e) => e.message, 'message', contains('SHA256 checksum mismatch'))),
        );
        expect(Directory(p.join(tempDir.path, 'acme.theme')).existsSync() &&
            File(p.join(tempDir.path, 'acme.theme', 'theme.json')).existsSync(), isFalse);
      });
    });
  });
}
