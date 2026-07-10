import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

void main() {
  group('ExtensionSupport', () {
    test('marks bare database drivers as preview-only', () {
      expect(
        ExtensionSupport.isPreviewOnly(ExtensionType.databaseDriver),
        isTrue,
      );
      expect(ExtensionSupport.isPreviewOnly(ExtensionType.theme), isFalse);
      expect(ExtensionSupport.isPreviewOnly(ExtensionType.script), isFalse);
    });

    test('lifts preview for drivers with valid process sandbox', () {
      const preview = ExtensionManifest(
        id: 'test.driver',
        name: 'Driver',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '*'},
      );
      expect(ExtensionSupport.isPreviewOnlyManifest(preview), isTrue);

      const ready = ExtensionManifest(
        id: 'test.driver',
        name: 'Driver',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '*'},
        sandbox: SandboxCapabilities(
          engine: SandboxEngine.process,
          network: NetworkPermission(
            mode: NetworkPermissionMode.connectionHostOnly,
            allowSsl: true,
          ),
        ),
      );
      expect(ExtensionSupport.isPreviewOnlyManifest(ready), isFalse);
    });

    test('scripts are never preview-only', () {
      const script = ExtensionManifest(
        id: 'test.sql-formatter',
        name: 'SQL Formatter',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.script,
        engines: {'querya_desktop': '*'},
        sandbox: SandboxCapabilities(engine: SandboxEngine.quickjs),
      );
      expect(ExtensionSupport.isPreviewOnlyManifest(script), isFalse);
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
