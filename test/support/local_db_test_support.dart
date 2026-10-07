import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
  @override
  Future<String?> getApplicationCachePath() async => _root;
  @override
  Future<String?> getLibraryPath() async => _root;
  @override
  Future<String?> getExternalStoragePath() async => _root;
  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];
  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [_root];
  @override
  Future<String?> getDownloadsPath() async => _root;
}

/// Points [LocalDb] at a fresh temporary directory. Call from `setUpAll` and
/// pass the result to [disposeTestLocalDb] in `tearDownAll`.
Future<Directory> initTestLocalDb(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  PathProviderPlatform.instance = _FakePathProvider(dir.path);
  await LocalDb.initFfi();
  // Open (and migrate) the database now, in the real zone. Opening it lazily
  // inside a widget test takes many real-async hops that each need a pump.
  await LocalDb.instance.getAppSetting('test_warmup');
  return dir;
}

Future<void> disposeTestLocalDb(Directory dir) async {
  await LocalDb.instance.close();
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}
