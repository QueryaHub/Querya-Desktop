import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// path_provider has no implementation in plain `flutter test`; LocalDb needs a path.
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
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [_root];

  @override
  Future<String?> getDownloadsPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_app_settings_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(null);
    await AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(null);
  });

  group('AppSettings', () {
    test('getPostgresSqlStmtTimeoutSeconds roundtrip', () async {
      expect(await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds(), isNull);

      await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(90);
      expect(await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds(), 90);

      await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(null);
      expect(await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds(), isNull);
    });

    test('getPostgresSqlStmtTimeoutSeconds returns null for invalid stored value', () async {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.postgresSqlStmtTimeoutSeconds,
        'not-a-number',
      );
      expect(await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds(), isNull);
    });

    test('getMysqlSqlStmtTimeoutSeconds roundtrip', () async {
      expect(await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds(), isNull);

      await AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(60);
      expect(await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds(), 60);

      await AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(null);
      expect(await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds(), isNull);
    });

    test('getMysqlSqlStmtTimeoutSeconds returns null for invalid stored value', () async {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.mysqlSqlStmtTimeoutSeconds,
        'not-a-number',
      );
      expect(await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds(), isNull);
    });
  });
}
