import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/theme/theme_paths.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory osSupport;
  late Directory installDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_app_data_root_');
    osSupport = Directory(p.join(tempDir.path, 'os_support'));
    await osSupport.create(recursive: true);
    installDir = Directory(p.join(tempDir.path, 'install'));
    await installDir.create(recursive: true);

    PathProviderPlatform.instance = _FakePathProvider(osSupport.path);
    AppDataRoot.resetMocks();
    AppDataRoot.mockInstallDirectory = installDir.path;
    // Avoid touching the developer's real ~/.local/share/com.example.* tree.
    AppDataRoot.mockLegacySupportCandidates = const [];
    ExtensionPaths.mockExtensionsDirectory = null;
    SandboxLogPaths.mockLogsDirectory = null;
  });

  tearDown(() async {
    AppDataRoot.resetMocks();
    ExtensionPaths.mockExtensionsDirectory = null;
    SandboxLogPaths.mockLogsDirectory = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppDataRoot', () {
    test('defaults to OS application support when not portable', () async {
      expect(await AppDataRoot.resolvePortableRoot(), isNull);
      expect(await AppDataRoot.isPortableMode(), isFalse);

      final support = await AppDataRoot.applicationSupportDirectory();
      expect(support.path, osSupport.path);
    });

    test('QUERYA_PORTABLE creates QueryaData next to install dir', () async {
      AppDataRoot.mockEnvironment = {'QUERYA_PORTABLE': '1'};

      final portable = await AppDataRoot.resolvePortableRoot();
      expect(portable, isNotNull);
      expect(portable!.path, p.join(installDir.path, 'QueryaData'));
      expect(await portable.exists(), isTrue);

      final support = await AppDataRoot.applicationSupportDirectory();
      expect(support.path, portable.path);
    });

    test('existing QueryaData sidecar enables portable without env', () async {
      final sidecar = Directory(p.join(installDir.path, 'QueryaData'));
      await sidecar.create(recursive: true);

      final portable = await AppDataRoot.resolvePortableRoot();
      expect(portable!.path, sidecar.path);
      expect(await AppDataRoot.isPortableMode(), isTrue);
    });

    test('APPIMAGE parent is used as install directory', () async {
      final appImage = p.join(installDir.path, 'Querya.AppImage');
      AppDataRoot.mockInstallDirectory = null;
      AppDataRoot.mockEnvironment = {
        'APPIMAGE': appImage,
        'QUERYA_PORTABLE': 'true',
      };

      final portable = await AppDataRoot.resolvePortableRoot();
      expect(portable!.path, p.join(installDir.path, 'QueryaData'));
    });

    test('themes and extensions redirect under portable root', () async {
      AppDataRoot.mockEnvironment = {'QUERYA_PORTABLE': 'yes'};
      final portable = await AppDataRoot.resolvePortableRoot();

      final themes = await ThemePaths.userThemesDirectory();
      expect(themes.path, p.join(portable!.path, 'themes'));

      final extensions = await ExtensionPaths.extensionsDirectory();
      expect(extensions.path, p.join(portable.path, 'extensions'));

      final logs = await SandboxLogPaths.logsDirectory();
      expect(logs.path, p.join(portable.path, 'logs'));
    });

    test('migrates legacy support dir when new location has no querya.db',
        () async {
      final legacy = Directory(p.join(tempDir.path, 'legacy_support'));
      final next = Directory(p.join(tempDir.path, 'new_support'));
      await Directory(p.join(legacy.path, 'querya_desktop'))
          .create(recursive: true);
      await File(p.join(legacy.path, 'querya_desktop', 'querya.db'))
          .writeAsString('legacy-db');
      await Directory(p.join(legacy.path, 'themes')).create(recursive: true);
      await File(p.join(legacy.path, 'themes', 'a.json')).writeAsString('{}');

      final migrated = await AppDataRoot.migrateLegacySupportIfNeeded(
        newSupport: next,
        legacyCandidates: [legacy],
      );

      expect(migrated, isTrue);
      expect(
        await File(p.join(next.path, 'querya_desktop', 'querya.db'))
            .readAsString(),
        'legacy-db',
      );
      expect(
        await File(p.join(next.path, 'themes', 'a.json')).exists(),
        isTrue,
      );

      final again = await AppDataRoot.migrateLegacySupportIfNeeded(
        newSupport: next,
        legacyCandidates: [legacy],
      );
      expect(again, isFalse);
    });
  });
}
