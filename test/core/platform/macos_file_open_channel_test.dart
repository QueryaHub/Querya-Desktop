import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/platform/macos_file_open_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacOsFileOpenChannel (#1589)', () {
    final service = FileLaunchService.instance;
    setUp(service.consumePendingTargets);
    tearDown(service.consumePendingTargets);

    test('queues the paths the app can open and skips the rest', () {
      final before = service.pendingRevision.value;

      final added = MacOsFileOpenChannel.queuePaths([
        '/Users/ann/reports/q1.sql',
        '/Users/ann/data/shop.sqlite',
        '/Users/ann/notes.txt',
        42,
      ]);

      expect(added, 2);
      expect(service.pendingTargets.map((t) => t.kind),
          [FileLaunchKind.sql, FileLaunchKind.sqlite]);
      expect(service.pendingRevision.value, before + 2);
    });

    test('anything that is not a list adds nothing', () {
      expect(MacOsFileOpenChannel.queuePaths(null), 0);
      expect(MacOsFileOpenChannel.queuePaths('/a.sql'), 0);
      expect(service.pendingTargets, isEmpty);
    });

    test('install is a no-op off macOS', () async {
      if (Platform.isMacOS) return;
      await MacOsFileOpenChannel.install();
      expect(service.pendingTargets, isEmpty);
    });
  });
}
