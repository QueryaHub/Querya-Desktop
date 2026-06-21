import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

void main() {
  group('LocalExtensionRegistry', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_extensions_test');
      ExtensionPaths.mockExtensionsDirectory = tempDir;
    });

    tearDown(() async {
      ExtensionPaths.mockExtensionsDirectory = null;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads extensions from manifest files', () async {
      // Create a valid extension folder
      final ext1Dir = Directory(p.join(tempDir.path, 'ext1'));
      await ext1Dir.create();
      
      final manifest1 = {
        'id': 'test.ext1',
        'name': 'Test Extension 1',
        'version': '1.0.0',
        'publisher': 'Test',
        'type': 'theme',
        'engines': {'querya_desktop': '^1.0.0'},
      };
      
      final file1 = File(p.join(ext1Dir.path, 'manifest.json'));
      await file1.writeAsString(jsonEncode(manifest1));

      // Create an invalid extension folder (no manifest)
      final ext2Dir = Directory(p.join(tempDir.path, 'ext2'));
      await ext2Dir.create();

      // Create a file that is not a directory
      final notADir = File(p.join(tempDir.path, 'not_a_dir.txt'));
      await notADir.writeAsString('I am a file');

      // Reload registry to scan the test directory
      await LocalExtensionRegistry.instance.reload();
      final manifests = LocalExtensionRegistry.instance.manifests;

      expect(manifests.length, 1);
      final loaded = manifests.first;
      expect(loaded.id, 'test.ext1');
      expect(loaded.type, ExtensionType.theme);
      expect(loaded.installPath, ext1Dir.path);
    });

    test('ignores directories with invalid manifest.json', () async {
      final extDir = Directory(p.join(tempDir.path, 'bad_ext'));
      await extDir.create();
      
      final file = File(p.join(extDir.path, 'manifest.json'));
      await file.writeAsString('{"invalid_json": '); // Syntax error

      await LocalExtensionRegistry.instance.reload();
      
      expect(LocalExtensionRegistry.instance.manifests, isEmpty);
    });
    
    test('returns cached manifests on subsequent load calls', () async {
      final extDir = Directory(p.join(tempDir.path, 'ext3'));
      await extDir.create();
      final file = File(p.join(extDir.path, 'manifest.json'));
      await file.writeAsString(jsonEncode({
        'id': 'test.ext3',
        'name': 'Test Ext 3',
        'version': '1.0.0',
        'publisher': 'Test',
        'type': 'theme',
        'engines': {}
      }));

      await LocalExtensionRegistry.instance.reload();
      expect(LocalExtensionRegistry.instance.manifests.length, 1);
      
      // Delete the file. load() shouldn't read from disk again unless reload() is called
      await file.delete();
      final manifests = await LocalExtensionRegistry.instance.load();
      expect(manifests.length, 1, reason: 'Should return cached result');
    });
  });
}
