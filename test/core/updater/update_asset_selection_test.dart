import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/installers/update_install_context.dart';
import 'package:querya_desktop/core/updater/update_asset_selection.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';

UpdateManifest _manifest(List<String> names) {
  return UpdateManifest(
    version: '0.5.0',
    changelog: '',
    assets: [
      for (final name in names)
        UpdateAsset(
          name: name,
          downloadUrl: 'https://example.com/$name',
        ),
    ],
  );
}

void main() {
  group('selectUpdateAsset', () {
    test('Linux AppImage runtime prefers .AppImage then zip', () {
      const ctx = UpdateInstallContext(
        environment: {'APPIMAGE': '/opt/Querya.AppImage'},
        resolvedExecutable: '/tmp/.mount_Querya/querya_desktop',
      );
      final asset = selectUpdateAsset(
        _manifest([
          'Querya-Desktop-0.5.0-linux.zip',
          'Querya-Desktop-0.5.0-linux.AppImage',
        ]),
        ctx,
        operatingSystem: 'linux',
      );
      expect(asset?.name, 'Querya-Desktop-0.5.0-linux.AppImage');
    });

    test('Linux portable prefers zip over AppImage', () {
      const ctx = UpdateInstallContext(
        environment: {},
        resolvedExecutable: '/home/u/Querya/querya_desktop',
      );
      final asset = selectUpdateAsset(
        _manifest([
          'Querya-Desktop-0.5.0-linux.AppImage',
          'Querya-Desktop-0.5.0-linux.zip',
        ]),
        ctx,
        operatingSystem: 'linux',
      );
      expect(asset?.name, 'Querya-Desktop-0.5.0-linux.zip');
    });

    test('Windows Inno install prefers setup.exe', () {
      const ctx = UpdateInstallContext(
        environment: {},
        resolvedExecutable: r'C:\Program Files\Querya\querya_desktop.exe',
      );
      final asset = selectUpdateAsset(
        _manifest([
          'Querya-Desktop-0.5.0-windows.zip',
          'Querya-Desktop-0.5.0-windows-setup.exe',
        ]),
        ctx,
        operatingSystem: 'windows',
        fileExists: (path) => path.toLowerCase().endsWith('unins000.exe'),
      );
      expect(asset?.name, 'Querya-Desktop-0.5.0-windows-setup.exe');
    });

    test('Windows portable prefers zip', () {
      const ctx = UpdateInstallContext(
        environment: {},
        resolvedExecutable: r'D:\portable\querya_desktop.exe',
      );
      final asset = selectUpdateAsset(
        _manifest([
          'Querya-Desktop-0.5.0-windows-setup.exe',
          'Querya-Desktop-0.5.0-windows.zip',
        ]),
        ctx,
        operatingSystem: 'windows',
        fileExists: (_) => false,
      );
      expect(asset?.name, 'Querya-Desktop-0.5.0-windows.zip');
    });

    test('macOS uses macos.zip', () {
      const ctx = UpdateInstallContext(
        environment: {},
        resolvedExecutable:
            '/Applications/querya_desktop.app/Contents/MacOS/querya_desktop',
      );
      final asset = selectUpdateAsset(
        _manifest([
          'Querya-Desktop-0.5.0-macos.zip',
          'Querya-Desktop-0.5.0-linux.zip',
        ]),
        ctx,
        operatingSystem: 'macos',
      );
      expect(asset?.name, 'Querya-Desktop-0.5.0-macos.zip');
    });
  });
}
