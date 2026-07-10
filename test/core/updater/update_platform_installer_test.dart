import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/updater/app_updater_service.dart';
import 'package:querya_desktop/core/updater/installers/update_install_context.dart';
import 'package:querya_desktop/core/updater/installers/update_install_utils.dart';
import 'package:querya_desktop/core/updater/update_platform_installer.dart';

void main() {
  group('UpdateInstallContext', () {
    test('detects AppImage runtime from APPIMAGE env', () {
      const ctx = UpdateInstallContext(
        environment: {'APPIMAGE': '/opt/Querya.AppImage'},
        resolvedExecutable: '/tmp/.mount_querya/querya_desktop',
      );
      expect(ctx.isLinuxAppImage, isTrue);
      expect(ctx.appImagePath, '/opt/Querya.AppImage');
    });

    test('detects snap and flatpak managed runtimes', () {
      const snap = UpdateInstallContext(
        environment: {'SNAP': 'querya'},
        resolvedExecutable: '/snap/bin/querya',
      );
      expect(snap.isSnap, isTrue);
      expect(snap.isManagedPackage, isTrue);

      const flatpak = UpdateInstallContext(
        environment: {'FLATPAK_ID': 'com.querya.desktop'},
        resolvedExecutable: '/app/bin/querya_desktop',
      );
      expect(flatpak.isFlatpak, isTrue);
      expect(flatpak.isManagedPackage, isTrue);
    });

    test('finds macOS .app bundle from executable path', () {
      expect(
        UpdateInstallContext.macAppBundlePathFromExecutable(
          '/Applications/Querya.app/Contents/MacOS/querya_desktop',
        ),
        '/Applications/Querya.app',
      );
    });
  });

  group('update install scripts', () {
    test('linux bundle script waits for pid and execs target', () {
      final script = buildLinuxBundleReplaceScript(
        pid: 4242,
        sourceDir: '/tmp/new',
        targetDir: '/opt/querya',
        executable: '/opt/querya/querya_desktop',
      );
      expect(script, contains('PID="4242"'));
      expect(script, contains('EXE="/opt/querya/querya_desktop"'));
      expect(script, contains('exec "\$EXE"'));
    });

    test('windows batch script waits for pid', () {
      final batch = buildWindowsReplaceBatch(
        pid: 99,
        sourceDir: 'C:\\tmp\\new',
        targetDir: 'C:\\Querya',
        executable: 'querya_desktop.exe',
      );
      expect(batch, contains('set PID=99'));
      expect(batch, contains('querya_desktop.exe'));
    });
  });

  group('extractZipSecurely', () {
    test('rejects path traversal entries', () async {
      final temp = await Directory.systemTemp.createTemp('querya_zip_test_');
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final zipFile = File(p.join(temp.path, 'evil.zip'));
      final archive = Archive();
      archive.addFile(ArchiveFile('../outside.txt', 4, [1, 2, 3, 4]));
      await zipFile.writeAsBytes(ZipEncoder().encode(archive)!);

      expect(
        () => extractZipSecurely(
          zipFile: zipFile,
          destinationDir: Directory(p.join(temp.path, 'out')),
        ),
        throwsA(isA<AppUpdaterException>()),
      );
    });
  });

  group('UpdatePlatformInstaller', () {
    test('blocks install on snap with package manager hint', () async {
      final installer = UpdatePlatformInstaller.forCurrentPlatform(
        context: const UpdateInstallContext(
          environment: {'SNAP': 'querya'},
          resolvedExecutable: '/snap/bin/querya',
        ),
      );

      await expectLater(
        installer.install(File('/tmp/update.zip')),
        throwsA(isA<PackageManagerUpdateRequiredException>()),
      );
    });
  });
}
