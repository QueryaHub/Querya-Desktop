import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/platform/open_directory.dart';

void main() {
  group('openDirectoryInFileManager', () {
    test('creates missing directory before delegating to opener', () async {
      final root = await Directory.systemTemp
          .createTemp('querya_open_directory_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final target = p.join(root.path, 'themes');
      String? openedPath;

      final opened = await openDirectoryInFileManager(
        target,
        opener: (path) async {
          openedPath = path;
          return true;
        },
      );

      expect(opened, isTrue);
      expect(openedPath, target);
      expect(await Directory(target).exists(), isTrue);
    });

    test('returns false when opener reports failure', () async {
      final root = await Directory.systemTemp
          .createTemp('querya_open_directory_fail_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final target = p.join(root.path, 'themes');
      final opened = await openDirectoryInFileManager(
        target,
        opener: (_) async => false,
      );

      expect(opened, isFalse);
      expect(await Directory(target).exists(), isTrue);
    });
  });
}
