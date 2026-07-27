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
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
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

    test('install rejects preview database drivers', () async {
      final repo = MockMarketplaceRepository();
      final trending = await repo.getTrending();
      final target = trending.firstWhere((e) => e.id == 'queryahub.clickhouse-driver');

      expect(
        () => repo.install(target),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('preview listings only'),
        )),
      );

      expect(
        LocalExtensionRegistry.instance.manifests.any((e) => e.id == target.id),
        isFalse,
      );
    });

    test('install rejects theme requesting excessive sandbox permissions',
        () async {
      final repo = MockMarketplaceRepository();
      final manifest = ExtensionManifest.fromJson(const {
        'id': 'test.greedy-theme',
        'name': 'Greedy Theme',
        'version': '1.0.0',
        'publisher': 'Test',
        'type': 'theme',
        'engines': {'querya_desktop': '*'},
        'sandbox': {
          'engine': 'process',
          'permissions': {
            'network': {'mode': 'connection_host_only'},
          },
        },
      });

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('sandbox permissions beyond the security policy'),
        )),
      );
    });

    test('install accepts database driver with valid process sandbox', () async {
      final repo = MockMarketplaceRepository();
      const manifest = ExtensionManifest(
        id: 'test.sandboxed-driver',
        name: 'Sandboxed Driver',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '*'},
        main: 'bin/driver',
        sandbox: SandboxCapabilities(
          engine: SandboxEngine.process,
          network: NetworkPermission(
            mode: NetworkPermissionMode.connectionHostOnly,
            allowSsl: true,
          ),
        ),
      );

      await repo.install(manifest);

      final extDir = Directory(p.join(tempDir.path, manifest.id));
      expect(await extDir.exists(), isTrue);
      expect(await File(p.join(extDir.path, 'manifest.json')).exists(), isTrue);
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
      final zipBytes = ZipEncoder().encode(archive);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      const manifest = ExtensionManifest(
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

    test('install aborts when SHA256 checksum is missing', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('test.txt', 4, utf8.encode('good')));
      final zipBytes = ZipEncoder().encode(archive);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      const manifest = ExtensionManifest(
        id: 'test.no-sha256',
        name: 'No SHA256',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.theme,
        engines: {'querya_desktop': '*'},
        downloadUrl: 'http://localhost:8000/test.zip',
      );

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('missing SHA256 checksum'),
        )),
      );
    });

    test('install aborts when SHA256 checksum is empty', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('test.txt', 4, utf8.encode('good')));
      final zipBytes = ZipEncoder().encode(archive);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      const manifest = ExtensionManifest(
        id: 'test.empty-sha256',
        name: 'Empty SHA256',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.theme,
        engines: {'querya_desktop': '*'},
        downloadUrl: 'http://localhost:8000/test.zip',
        sha256Checksum: '   ',
      );

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('missing SHA256 checksum'),
        )),
      );
    });

    test('install prevents Path Traversal during archive unpacking (Issue #242)', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')));
      final zipBytes = ZipEncoder().encode(archive);
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
    test('install rejects preview database drivers', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('index.js', 4, utf8.encode('stub')));
      final zipBytes = ZipEncoder().encode(archive);
      final expectedSha256 = sha256.convert(zipBytes).toString();

      final mockClient = MockClient((request) async {
        return http.Response.bytes(zipBytes, 200);
      });

      final repo = HttpMarketplaceRepository(client: mockClient);
      final manifest = ExtensionManifest(
        id: 'test.driver',
        name: 'Driver Test',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: const {'querya_desktop': '*'},
        main: 'index.js',
        downloadUrl: 'http://localhost:8000/driver.zip',
        sha256Checksum: expectedSha256,
      );

      expect(
        () => repo.install(manifest),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('preview listings only'),
        )),
      );
    });

    test('download rejects disallowed URLs when release policy is enforced',
        () async {
      final repo = HttpMarketplaceRepository(
        baseUrl: 'https://cdn.example.com/api/v1',
        extraTrustedDownloadHosts: ['cdn.example.com'],
        allowLocalhostInDebug: false,
        client: MockClient((request) async => http.Response('', 200)),
      );

      expect(
        () => repo.download('http://cdn.example.com/test.zip'),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('Download URL is not allowed'),
        )),
      );

      expect(
        () => repo.download('https://127.0.0.1/test.zip'),
        throwsA(isA<MarketplaceException>()),
      );

      expect(
        () => repo.download('file:///tmp/test.zip'),
        throwsA(isA<MarketplaceException>()),
      );
    });
  });
}



