import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
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
  });
}
