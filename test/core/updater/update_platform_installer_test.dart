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
      expect(flatpak.packageManagerUpdateCommand, 'flatpak update');
      expect(snap.packageManagerUpdateCommand, 'snap refresh');
    });

    test('does not treat generic container env as Flatpak', () {
      const docker = UpdateInstallContext(
        environment: {'container': 'oci'},
        resolvedExecutable: '/app/querya_desktop',
      );
      expect(docker.isFlatpak, isFalse);
      expect(docker.isManagedPackage, isFalse);
      expect(docker.packageManagerUpdateCommand, isNull);
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
      expect(script, contains("EXE='/opt/querya/querya_desktop'"));
      expect(script, contains('refusing replace'));
      expect(script, contains('exec "\$EXE"'));
    });

    test('resolves nested Flutter zip layout and refuses garbage', () async {
      final temp = await Directory.systemTemp.createTemp('querya_bundle_');
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final nested = Directory(p.join(temp.path, 'Querya-Desktop-0.5.0-linux'));
      await nested.create();
      await File(p.join(nested.path, 'querya_desktop')).writeAsString('exe');
      await Directory(p.join(nested.path, 'lib')).create();

      final resolved = resolveLinuxFlutterBundleRoot(
        extractDir: temp,
        executableName: 'querya_desktop',
      );
      expect(resolved.path, nested.path);

      final junk = await Directory.systemTemp.createTemp('querya_junk_');
      addTearDown(() async {
        if (await junk.exists()) {
          await junk.delete(recursive: true);
        }
      });
      await File(p.join(junk.path, 'readme.txt')).writeAsString('no bundle');
      expect(
        () => resolveLinuxFlutterBundleRoot(
          extractDir: junk,
          executableName: 'querya_desktop',
        ),
        throwsA(isA<AppUpdaterException>()),
      );
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
      await zipFile.writeAsBytes(ZipEncoder().encode(archive));

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
