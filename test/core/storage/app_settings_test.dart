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
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.sqlResultMaxRows);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.sqlEditorFontSizePoints);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.sqlHistoryMaxEntries);
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

    test('getSqlResultMaxRows defaults and normalizes to preset', () async {
      expect(await AppSettings.instance.getSqlResultMaxRows(), kDefaultSqlResultMaxRows);

      await AppSettings.instance.setSqlResultMaxRows(10000);
      expect(await AppSettings.instance.getSqlResultMaxRows(), 10000);

      await LocalDb.instance.setAppSetting(AppSettingsKeys.sqlResultMaxRows, '7777');
      expect(await AppSettings.instance.getSqlResultMaxRows(), 10000);

      await LocalDb.instance.setAppSetting(AppSettingsKeys.sqlResultMaxRows, 'not-int');
      expect(await AppSettings.instance.getSqlResultMaxRows(), kDefaultSqlResultMaxRows);
    });

    test('getSqlEditorFontSize roundtrip and invalid stored', () async {
      expect(await AppSettings.instance.getSqlEditorFontSize(), kDefaultSqlEditorFontSize);

      await AppSettings.instance.setSqlEditorFontSize(16);
      expect(await AppSettings.instance.getSqlEditorFontSize(), 16);

      await LocalDb.instance.setAppSetting(AppSettingsKeys.sqlEditorFontSizePoints, '99');
      expect(await AppSettings.instance.getSqlEditorFontSize(), 24);

      await LocalDb.instance.setAppSetting(AppSettingsKeys.sqlEditorFontSizePoints, 'x');
      expect(await AppSettings.instance.getSqlEditorFontSize(), kDefaultSqlEditorFontSize);
    });

    test('setSqlResultMaxRows snaps non-preset to nearest', () async {
      await AppSettings.instance.setSqlResultMaxRows(3333);
      expect(await AppSettings.instance.getSqlResultMaxRows(), 2500);

      await AppSettings.instance.setSqlResultMaxRows(8000);
      expect(await AppSettings.instance.getSqlResultMaxRows(), 10000);
    });

    test('setSqlEditorFontSize clamps to 10–24', () async {
      await AppSettings.instance.setSqlEditorFontSize(8);
      expect(await AppSettings.instance.getSqlEditorFontSize(), 10);

      await AppSettings.instance.setSqlEditorFontSize(30);
      expect(await AppSettings.instance.getSqlEditorFontSize(), 24);
    });

    test('getSqlHistoryMaxEntries defaults and normalizes', () async {
      expect(
        await AppSettings.instance.getSqlHistoryMaxEntries(),
        kDefaultSqlHistoryMaxEntries,
      );

      await AppSettings.instance.setSqlHistoryMaxEntries(200);
      expect(await AppSettings.instance.getSqlHistoryMaxEntries(), 200);

      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.sqlHistoryMaxEntries,
        '40',
      );
      expect(await AppSettings.instance.getSqlHistoryMaxEntries(), 50);

      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.sqlHistoryMaxEntries,
        'not-int',
      );
      expect(
        await AppSettings.instance.getSqlHistoryMaxEntries(),
        kDefaultSqlHistoryMaxEntries,
      );
    });

    test('setSqlHistoryMaxEntries snaps non-preset to nearest', () async {
      await AppSettings.instance.setSqlHistoryMaxEntries(30);
      expect(await AppSettings.instance.getSqlHistoryMaxEntries(), 25);

      await AppSettings.instance.setSqlHistoryMaxEntries(180);
      expect(await AppSettings.instance.getSqlHistoryMaxEntries(), 200);
    });
  });

  group('AppSettingsRevision', () {
    test('bump increments listenable value', () {
      final start = AppSettingsRevision.listenable.value;
      AppSettingsRevision.bump();
      expect(AppSettingsRevision.listenable.value, start + 1);
    });

    test('mutating AppSettings notifies listenable', () async {
      var calls = 0;
      void listener() => calls++;

      AppSettingsRevision.listenable.addListener(listener);
      final before = AppSettingsRevision.listenable.value;
      await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(45);
      expect(AppSettingsRevision.listenable.value, greaterThan(before));
      expect(calls, greaterThan(0));
      AppSettingsRevision.listenable.removeListener(listener);
    });
  });
}
