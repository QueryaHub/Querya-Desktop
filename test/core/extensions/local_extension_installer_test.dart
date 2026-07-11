import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_installer.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

ArchiveFile _jsonFile(String name, Map<String, Object?> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ArchiveFile(name, bytes.length, bytes);
}

Future<File> _writeZip(Directory dir, Archive archive, String name) async {
  final bytes = ZipEncoder().encode(archive);
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  group('LocalExtensionInstaller', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_local_ext_');
      ExtensionPaths.mockExtensionsDirectory = tempDir;
      await LocalExtensionRegistry.instance.reload();
    });

    tearDown(() async {
      ExtensionPaths.mockExtensionsDirectory = null;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('installs theme package with root-level manifest', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'community.local-theme',
          'name': 'Local Theme',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'theme',
          'engines': {'querya_desktop': '*'},
          'main': 'theme.json',
        }))
        ..addFile(_jsonFile('theme.json', {
          'name': 'Local Theme',
          'type': 'dark',
          'colors': {'editor.background': '#111111'},
        }));

      final zip = await _writeZip(tempDir, archive, 'theme.zip');
      final installer = LocalExtensionInstaller();
      final installed = await installer.installFromArchive(zip);

      expect(installed.id, 'community.local-theme');
      final extDir = Directory(p.join(tempDir.path, 'community.local-theme'));
      expect(await File(p.join(extDir.path, 'manifest.json')).exists(), isTrue);
      expect(await File(p.join(extDir.path, 'theme.json')).exists(), isTrue);
      expect(
        LocalExtensionRegistry.instance.manifests.any(
          (m) => m.id == 'community.local-theme',
        ),
        isTrue,
      );
    });

    test('strips single root folder from archive', () async {
      final archive = Archive()
        ..addFile(_jsonFile('my-ext/manifest.json', {
          'id': 'test.nested',
          'name': 'Nested',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'theme',
          'engines': {'querya_desktop': '*'},
        }))
        ..addFile(ArchiveFile('my-ext/readme.txt', 4, utf8.encode('hi\n')));

      final zip = await _writeZip(tempDir, archive, 'nested.zip');
      await LocalExtensionInstaller().installFromArchive(zip);

      final extDir = Directory(p.join(tempDir.path, 'test.nested'));
      expect(await File(p.join(extDir.path, 'manifest.json')).exists(), isTrue);
      expect(await File(p.join(extDir.path, 'readme.txt')).exists(), isTrue);
      expect(await Directory(p.join(extDir.path, 'my-ext')).exists(), isFalse);
    });

    test('rejects path traversal entries', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.evil',
          'name': 'Evil',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'theme',
          'engines': {'querya_desktop': '*'},
        }))
        ..addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')));

      final zip = await _writeZip(tempDir, archive, 'evil.zip');
      expect(
        () => LocalExtensionInstaller().installFromArchive(zip),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('Path traversal'),
        )),
      );
      expect(await Directory(p.join(tempDir.path, 'test.evil')).exists(), isFalse);
    });

    test('rejects preview database drivers without process sandbox', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.driver',
          'name': 'Driver',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'database_driver',
          'engines': {'querya_desktop': '*'},
          'main': 'bin/driver',
        }))
        ..addFile(ArchiveFile('bin/driver', 4, utf8.encode('stub')));

      final zip = await _writeZip(tempDir, archive, 'driver.zip');
      expect(
        () => LocalExtensionInstaller().installFromArchive(zip),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('preview'),
        )),
      );
    });

    test('rejects SHA256 mismatch', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.sha',
          'name': 'SHA',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'theme',
          'engines': {'querya_desktop': '*'},
        }));
      final zip = await _writeZip(tempDir, archive, 'sha.zip');
      expect(
        () => LocalExtensionInstaller().installFromArchive(
          zip,
          expectedSha256: '0' * 64,
        ),
        throwsA(isA<MarketplaceException>().having(
          (e) => e.message,
          'message',
          contains('SHA256'),
        )),
      );
    });

    test('accepts matching SHA256', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.sha-ok',
          'name': 'SHA OK',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'theme',
          'engines': {'querya_desktop': '*'},
        }));
      final zipBytes = ZipEncoder().encode(archive);
      final zip = File(p.join(tempDir.path, 'ok.zip'));
      await zip.writeAsBytes(zipBytes);
      final digest = sha256.convert(zipBytes).toString();

      final installed = await LocalExtensionInstaller().installFromArchive(
        zip,
        expectedSha256: digest,
      );
      expect(installed.id, 'test.sha-ok');
    });

    test('preserves contributions and capabilities in installed manifest',
        () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.clickhouse',
          'name': 'CH',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'database_driver',
          'engines': {'querya_desktop': '*'},
          'main': 'bin/driver',
          'capabilities': {
            'databaseDriver': true,
            'sduiForms': true,
          },
          'sandbox': {
            'engine': 'process',
            'permissions': {
              'network': {'mode': 'connection_host_only', 'allow_ssl': true},
              'filesystem': {'scratch_mb': 100, 'access': 'scratch_only'},
              'resources': {'memory_mb': 256, 'max_open_files': 64},
            },
          },
          'contributions': {
            'drivers': [
              {
                'driverId': 'clickhouse',
                'displayName': 'ClickHouse',
                'defaultPort': 8123,
                'connectionFormSchema': 'assets/connection_form.json',
              }
            ]
          },
        }))
        ..addFile(ArchiveFile('bin/driver', 4, utf8.encode('stub')));

      final zip = await _writeZip(tempDir, archive, 'ch.zip');
      final installed =
          await LocalExtensionInstaller().installFromArchive(zip);

      expect(installed.contributedDrivers, hasLength(1));
      expect(installed.contributedDrivers.first.driverId, 'clickhouse');
      expect(installed.capabilities?.databaseDriver, isTrue);

      final onDisk = await File(
        p.join(tempDir.path, 'test.clickhouse', 'manifest.json'),
      ).readAsString();
      final decoded = jsonDecode(onDisk) as Map<String, dynamic>;
      expect(decoded['contributions'], isA<Map>());
      expect(decoded['capabilities'], isA<Map>());
      expect(
        (decoded['contributions'] as Map)['drivers'],
        isA<List>(),
      );
    });

    test('marks database driver bin entry executable after install', () async {
      final archive = Archive()
        ..addFile(_jsonFile('manifest.json', {
          'id': 'test.driver-exec',
          'name': 'Driver',
          'version': '1.0.0',
          'publisher': 'Test',
          'type': 'database_driver',
          'engines': {'querya_desktop': '*'},
          'main': 'bin/driver',
          'sandbox': {
            'engine': 'process',
            'permissions': {
              'network': {'mode': 'connection_host_only', 'allow_ssl': true},
              'filesystem': {'scratch_mb': 100, 'access': 'scratch_only'},
              'resources': {'memory_mb': 256, 'max_open_files': 64},
            },
          },
        }))
        ..addFile(ArchiveFile('bin/driver', 4, utf8.encode('stub')));

      final zip = await _writeZip(tempDir, archive, 'driver-exec.zip');
      await LocalExtensionInstaller().installFromArchive(zip);

      final entry = File(p.join(tempDir.path, 'test.driver-exec', 'bin', 'driver'));
      final mode = await entry.stat().then((s) => s.mode);
      expect(mode & 0x111, isNot(0));
    });
  });
}
