import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_installer.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';

const _id = 'community.sideload-theme';

ArchiveFile _text(String name, String body) {
  final bytes = utf8.encode(body);
  return ArchiveFile(name, bytes.length, bytes);
}

Archive _themePackage(String version, {Map<String, String> extra = const {}}) {
  final archive = Archive()
    ..addFile(_text(
      'manifest.json',
      jsonEncode({
        'id': _id,
        'name': 'Sideload Theme',
        'version': version,
        'publisher': 'E2E',
        'type': 'theme',
        'engines': {'querya_desktop': '*'},
        'main': 'theme.json',
      }),
    ))
    ..addFile(_text(
      'theme.json',
      jsonEncode({
        'name': 'Sideload Theme',
        'type': 'dark',
        'colors': {'editor.background': '#101010'},
      }),
    ));
  extra.forEach((name, body) => archive.addFile(_text(name, body)));
  return archive;
}

void main() {
  late Directory root;
  late Directory extensions;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('querya_e2e_sideload_');
    extensions = Directory(p.join(root.path, 'extensions'))..createSync();
    ExtensionPaths.mockExtensionsDirectory = extensions;
    await LocalExtensionRegistry.instance.reload();
  });

  tearDown(() async {
    ExtensionPaths.mockExtensionsDirectory = null;
    await LocalExtensionRegistry.instance.reload();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(Archive archive, String name) async {
    final file = File(p.join(root.path, name));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  String? installedVersion() {
    for (final m in LocalExtensionRegistry.instance.manifests) {
      if (m.id == _id) return m.version;
    }
    return null;
  }

  test('a .qext package is sideloaded, reported and listed in the registry',
      () async {
    final file = await write(_themePackage('1.0.0'), 'theme.qext');
    final progress = <double>[];

    final manifest = await LocalExtensionInstaller()
        .installFromPath(file.path, onProgress: progress.add);

    expect(manifest.id, _id);
    expect(progress.last, 1.0);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(File(p.join(extensions.path, _id, 'theme.json')).existsSync(),
        isTrue);
    expect(installedVersion(), '1.0.0');
  });

  test('installing a newer version replaces the files and stops live sessions',
      () async {
    final stopped = <String>[];
    final installer = LocalExtensionInstaller(
      stopSessionsForExtension: (id) async => stopped.add(id),
    );
    await installer.installFromPath(
      (await write(_themePackage('1.0.0', extra: {'old.txt': 'v1'}), 'v1.qext'))
          .path,
    );
    await installer.installFromPath(
      (await write(_themePackage('2.0.0', extra: {'new.txt': 'v2'}), 'v2.qext'))
          .path,
    );

    expect(stopped, [_id, _id]);
    expect(installedVersion(), '2.0.0');
    final dir = p.join(extensions.path, _id);
    expect(File(p.join(dir, 'new.txt')).existsSync(), isTrue);
    expect(File(p.join(dir, 'old.txt')).existsSync(), isFalse);
  });

  test('a matching SHA-256 installs, a wrong one aborts before any change',
      () async {
    final file = await write(_themePackage('1.0.0'), 'theme.qext');
    final good = await sha256HexOfFile(file);

    await expectLater(
      LocalExtensionInstaller()
          .installFromPath(file.path, expectedSha256: '0' * 64),
      throwsA(isA<MarketplaceException>().having(
          (e) => e.message, 'message', contains('SHA256 checksum mismatch'))),
    );
    expect(Directory(p.join(extensions.path, _id)).existsSync(), isFalse);

    await LocalExtensionInstaller()
        .installFromPath(file.path, expectedSha256: good.toUpperCase());
    expect(installedVersion(), '1.0.0');
  });

  test('an archive without a manifest is refused and the installed copy stays',
      () async {
    final installer = LocalExtensionInstaller();
    await installer.installFromPath(
      (await write(_themePackage('1.0.0'), 'v1.qext')).path,
    );

    final broken = Archive()..addFile(_text('readme.txt', 'no manifest'));
    await expectLater(
      installer.installFromPath((await write(broken, 'broken.qext')).path),
      throwsA(isA<MarketplaceException>().having(
          (e) => e.message, 'message', contains('manifest.json'))),
    );

    expect(installedVersion(), '1.0.0');
    expect(File(p.join(extensions.path, _id, 'theme.json')).existsSync(),
        isTrue);
  });

  test('a missing file is reported instead of crashing', () async {
    await expectLater(
      LocalExtensionInstaller()
          .installFromPath(p.join(root.path, 'absent.qext')),
      throwsA(isA<MarketplaceException>().having(
          (e) => e.message, 'message', contains('not found'))),
    );
  });
}
