import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

void main() {
  group('ExtensionSupport', () {
    test('marks database drivers as preview-only', () {
      expect(
        ExtensionSupport.isPreviewOnly(ExtensionType.databaseDriver),
        isTrue,
      );
      expect(ExtensionSupport.isPreviewOnly(ExtensionType.theme), isFalse);
    });

    test('validateDriverPackage requires main entry file', () async {
      final dir = await Directory.systemTemp.createTemp('querya_driver_test_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      const manifest = ExtensionManifest(
        id: 'test.driver',
        name: 'Test Driver',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '^0.4.7'},
        main: 'index.js',
      );

      expect(
        () => ExtensionSupport.validateDriverPackage(
          manifest: manifest,
          installDir: dir,
        ),
        throwsA(isA<MarketplaceException>()),
      );

      await File(p.join(dir.path, 'index.js')).writeAsString('// stub');
      expect(
        () => ExtensionSupport.validateDriverPackage(
          manifest: manifest,
          installDir: dir,
        ),
        returnsNormally,
      );
    });
  });
}
