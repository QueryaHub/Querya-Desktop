import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/motion/querya_motion_controller.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_motion_controller_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('QueryaMotionController default/off/reduced logic', () async {
    final controller = QueryaMotionController.instance;

    // Initially loads default (full)
    await controller.load();
    expect(controller.level, QueryaMotionLevel.full);

    var notifyCount = 0;
    void listener() => notifyCount++;
    controller.addListener(listener);

    try {
      // Sets and persists reduced
      await controller.setLevel(QueryaMotionLevel.reduced);
      expect(controller.level, QueryaMotionLevel.reduced);
      expect(notifyCount, 1);

      // Sets and persists off
      await controller.setLevel(QueryaMotionLevel.off);
      expect(controller.level, QueryaMotionLevel.off);
      expect(notifyCount, 2);

      // Same level does not notify
      await controller.setLevel(QueryaMotionLevel.off);
      expect(notifyCount, 2);

      // Load from DB restores level
      final anotherController = QueryaMotionController.instance;
      await anotherController.load();
      expect(anotherController.level, QueryaMotionLevel.off);
    } finally {
      controller.removeListener(listener);
    }
  });
}
