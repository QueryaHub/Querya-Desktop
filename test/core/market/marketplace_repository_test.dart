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
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

void main() {
  group('MockMarketplaceRepository', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_market_test_');
      ExtensionPaths.mockExtensionsDirectory = tempDir;
      await LocalExtensionRegistry.instance.reload();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      ExtensionPaths.mockExtensionsDirectory = null;
    });

    test('getTrending returns default seed items', () async {
      final repo = MockMarketplaceRepository();
      final trending = await repo.getTrending();
      expect(trending, isNotEmpty);
      expect(trending.any((e) => e.id == 'queryahub.clickhouse-driver'), isTrue);
      expect(trending.any((e) => e.id == 'queryahub.cyberpunk-neon'), isTrue);
    });

    test('search filters by name, id, description, and tags', () async {
      final repo = MockMarketplaceRepository();
      
      final byName = await repo.search('ClickHouse');
      expect(byName.length, 1);
      expect(byName.first.id, 'queryahub.clickhouse-driver');

      final byTag = await repo.search('neon');
      expect(byTag.length, 1);
      expect(byTag.first.id, 'queryahub.cyberpunk-neon');

      final empty = await repo.search('nonexistent_extension_query_12345');
      expect(empty, isEmpty);
    });

    test('install writes manifest to disk and reloads LocalExtensionRegistry', () async {
      final repo = MockMarketplaceRepository();
      final trending = await repo.getTrending();
      final target = trending.firstWhere((e) => e.id == 'queryahub.clickhouse-driver');

      final progressValues = <double>[];
      await repo.install(target, onProgress: (p) => progressValues.add(p));

      expect(progressValues, isNotEmpty);
      expect(progressValues.last, 1.0);

      expect(LocalExtensionRegistry.instance.manifests.any((e) => e.id == target.id), isTrue);
      
      final extDir = Directory(p.join(tempDir.path, target.id));
      expect(await extDir.exists(), isTrue);
      expect(await File(p.join(extDir.path, 'manifest.json')).exists(), isTrue);
    });

    test('uninstall removes directory and updates LocalExtensionRegistry', () async {
      final repo = MockMarketplaceRepository();
      final trending = await repo.getTrending();
      final target = trending.firstWhere((e) => e.id == 'queryahub.clickhouse-driver');

      await repo.install(target);
      expect(LocalExtensionRegistry.instance.manifests.any((e) => e.id == target.id), isTrue);

      await repo.uninstall(target.id);
      expect(LocalExtensionRegistry.instance.manifests.any((e) => e.id == target.id), isFalse);
      expect(await Directory(p.join(tempDir.path, target.id)).exists(), isFalse);
    });

    test('install theme creates theme.json in extension directory', () async {
      final repo = MockMarketplaceRepository();
      final trending = await repo.getTrending();
      final target = trending.firstWhere((e) => e.id == 'queryahub.cyberpunk-neon');

      await repo.install(target);

      final extDir = Directory(p.join(tempDir.path, target.id));
      expect(await extDir.exists(), isTrue);
      expect(await File(p.join(extDir.path, 'manifest.json')).exists(), isTrue);
      expect(await File(p.join(extDir.path, 'theme.json')).exists(), isTrue);
    });
  });

  group('HttpMarketplaceRepository', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_http_market_test_');
      ExtensionPaths.mockExtensionsDirectory = tempDir;
      await LocalExtensionRegistry.instance.reload();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      ExtensionPaths.mockExtensionsDirectory = null;
    });

    test('getTrending fetches from backend API', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/extensions/trending');
        return http.Response(jsonEncode([
          {
            'id': 'test.extension',
            'name': 'Test Ext',
            'version': '1.0.0',
            'publisher': 'Test',
            'type': 'theme',
            'engines': {'querya_desktop': '*'},
          }
        ]), 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      final trending = await repo.getTrending();
      expect(trending.length, 1);
      expect(trending.first.id, 'test.extension');
    });

    test('search queries backend API', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/extensions/search');
        expect(request.url.queryParameters['q'], 'sql');
        return http.Response(jsonEncode([
          {
            'id': 'test.sql',
            'name': 'SQL Tools',
            'version': '1.0.0',
            'publisher': 'Test',
            'type': 'databaseDriver',
            'engines': {'querya_desktop': '*'},
          }
        ]), 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      final results = await repo.search('sql');
      expect(results.length, 1);
      expect(results.first.name, 'SQL Tools');
    });

    test('install throws MarketplaceException on SHA256 checksum mismatch', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('test.txt', 4, utf8.encode('good')));
      final zipBytes = ZipEncoder().encode(archive)!;

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      final manifest = const ExtensionManifest(
        id: 'test.sha256',
        name: 'SHA256 Test',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.theme,
        engines: {'querya_desktop': '*'},
        downloadUrl: 'http://localhost:8000/test.zip',
        sha256Checksum: '0000000000000000000000000000000000000000000000000000000000000000',
      );

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('SHA256 checksum mismatch'),
        )),
      );
    });

    test('install prevents Path Traversal during archive unpacking (Issue #242)', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')));
      final zipBytes = ZipEncoder().encode(archive)!;
      final expectedSha256 = sha256.convert(zipBytes).toString();

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      final manifest = ExtensionManifest(
        id: 'test.traversal',
        name: 'Traversal Test',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.theme,
        engines: const {'querya_desktop': '*'},
        downloadUrl: 'http://localhost:8000/evil.zip',
        sha256Checksum: expectedSha256,
      );

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('Security violation'),
        )),
      );
    });
  });
}



