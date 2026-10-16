import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

void main() {
  group('manifest format', () {
    ExtensionManifest withFormat(int format) => ExtensionManifest(
          manifestVersion: format,
          id: 'test.fmt',
          name: 'Fmt',
          version: '1.0.0',
          publisher: 'Test',
          type: ExtensionType.theme,
          engines: const {'querya_desktop': '*'},
        );

    test('this build reads its own format and older ones', () {
      expect(ExtensionSupport.manifestFormatProblem(withFormat(1)), isNull);
      expect(
        ExtensionSupport.manifestFormatProblem(
            withFormat(ExtensionManifest.currentManifestVersion)),
        isNull,
      );
    });

    test('a newer format is refused with a message that says what to do', () {
      final problem = ExtensionSupport.manifestFormatProblem(
          withFormat(ExtensionManifest.currentManifestVersion + 1));
      expect(problem, contains('test.fmt'));
      expect(problem, contains('Update Querya Desktop'));
    });

    test('fromJson: absent or invalid reads as 1; toJson keeps only a real one',
        () {
      Map<String, dynamic> json(Object? v) => {
            'id': 'a.b',
            'name': 'A',
            'type': 'theme',
            if (v != null) 'manifestVersion': v,
          };
      expect(ExtensionManifest.fromJson(json(null)).manifestVersion, 1);
      expect(ExtensionManifest.fromJson(json('2')).manifestVersion, 1);
      expect(ExtensionManifest.fromJson(json(0)).manifestVersion, 1);
      final v3 = ExtensionManifest.fromJson(json(3));
      expect(v3.manifestVersion, 3);
      expect(v3.toJson()['manifestVersion'], 3);
      expect(ExtensionManifest.fromJson(json(1)).toJson(),
          isNot(contains('manifestVersion')));
    });
  });

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
