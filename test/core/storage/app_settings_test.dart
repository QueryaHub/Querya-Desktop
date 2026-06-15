import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    await AppSettings.instance.clearThemeSettings();
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

  group('theme settings', () {
    test('theme mode and preset roundtrip', () async {
      expect(await AppSettings.instance.getThemeMode(), ThemeMode.dark);
      expect(
        await AppSettings.instance.getThemePreset(),
        QueryaThemePreset.queryaDark,
      );

      await AppSettings.instance.setThemeMode(ThemeMode.light);
      await AppSettings.instance.setThemePreset(QueryaThemePreset.queryaLight);
      expect(await AppSettings.instance.getThemeMode(), ThemeMode.light);
      expect(
        await AppSettings.instance.getThemePreset(),
        QueryaThemePreset.queryaLight,
      );

      await AppSettings.instance.clearThemeSettings();
      expect(await AppSettings.instance.getThemeMode(), ThemeMode.dark);
    });

    test('theme animation defaults off and roundtrip', () async {
      expect(await AppSettings.instance.getThemeAnimationEnabled(), isFalse);

      await AppSettings.instance.setThemeAnimationEnabled(true);
      expect(await AppSettings.instance.getThemeAnimationEnabled(), isTrue);

      await AppSettings.instance.setThemeAnimationEnabled(false);
      expect(await AppSettings.instance.getThemeAnimationEnabled(), isFalse);

      await AppSettings.instance.setThemeAnimationEnabled(true);
      await AppSettings.instance.clearThemeSettings();
      expect(await AppSettings.instance.getThemeAnimationEnabled(), isFalse);
    });

    test('theme color overrides json roundtrip', () async {
      await AppSettings.instance.setThemeColorOverrides({
        'sideBar.background': '#ff0000',
        'editor.background': '#1e1e1e',
      });
      expect(await AppSettings.instance.getThemeColorOverrides(), {
        'sideBar.background': '#ff0000',
        'editor.background': '#1e1e1e',
      });
      await AppSettings.instance.clearThemeColorOverrides();
      expect(await AppSettings.instance.getThemeColorOverrides(), isEmpty);
    });

    test('selected theme registry id/source/path roundtrip', () async {
      expect(await AppSettings.instance.getSelectedThemeId(), isNull);
      expect(await AppSettings.instance.getSelectedThemeSource(), isNull);
      expect(await AppSettings.instance.getSelectedThemePath(), isNull);

      await AppSettings.instance.setSelectedThemeId('fixture-custom-dark');
      await AppSettings.instance.setSelectedThemeSource('filesystem');
      await AppSettings.instance.setSelectedThemePath(
        '/data/themes/fixture-custom-dark.json',
      );

      expect(
        await AppSettings.instance.getSelectedThemeId(),
        'fixture-custom-dark',
      );
      expect(
        await AppSettings.instance.getSelectedThemeSource(),
        'filesystem',
      );
      expect(
        await AppSettings.instance.getSelectedThemePath(),
        '/data/themes/fixture-custom-dark.json',
      );
    });

    test('clearSelectedThemeRegistry clears registry selection', () async {
      await AppSettings.instance.setSelectedThemeId('fixture-custom-dark');
      await AppSettings.instance.setSelectedThemeSource('imported');
      await AppSettings.instance.setSelectedThemePath('/tmp/theme.json');

      await AppSettings.instance.clearSelectedThemeRegistry();

      expect(await AppSettings.instance.getSelectedThemeId(), isNull);
      expect(await AppSettings.instance.getSelectedThemeSource(), isNull);
      expect(await AppSettings.instance.getSelectedThemePath(), isNull);
    });

    test('clearThemeSettings clears selected registry theme', () async {
      await AppSettings.instance.setSelectedThemeId('fixture-custom-light');
      await AppSettings.instance.setSelectedThemeSource('filesystem');
      await AppSettings.instance.setSelectedThemePath('/tmp/light.json');

      await AppSettings.instance.clearThemeSettings();

      expect(await AppSettings.instance.getSelectedThemeId(), isNull);
      expect(await AppSettings.instance.getSelectedThemeSource(), isNull);
      expect(await AppSettings.instance.getSelectedThemePath(), isNull);
    });
  });

  group('ui scale', () {
    test('defaults to 1.0 and stores continuous 1% steps', () async {
      expect(await AppSettings.instance.getUiScale(), kDefaultUiScale);

      await AppSettings.instance.setUiScale(1.12, fine: true);
      expect(await AppSettings.instance.getUiScale(), closeTo(1.12, 0.001));

      await AppSettings.instance.setUiScale(0.75);
      expect(await AppSettings.instance.getUiScale(), kMinUiScale);

      await AppSettings.instance.setUiScale(2.5);
      expect(await AppSettings.instance.getUiScale(), kMaxUiScale);

      await AppSettings.instance.setUiScale(1.12, fine: false);
      expect(await AppSettings.instance.getUiScale(), 1.1);

      await LocalDb.instance.deleteAppSetting(AppSettingsKeys.uiScale);
    });
  });

  group('AppSettingsRevision', () {
    test('bump increments listenable value', () {
      final start = AppSettingsRevision.listenable.value;
      AppSettingsRevision.bump();
      expect(AppSettingsRevision.listenable.value, start + 1);
    });

    test('mutating SQL workspace settings notifies SqlWorkspaceSettingsRevision',
        () async {
      var calls = 0;
      void listener() => calls++;

      SqlWorkspaceSettingsRevision.listenable.addListener(listener);
      final before = SqlWorkspaceSettingsRevision.listenable.value;
      await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(45);
      expect(SqlWorkspaceSettingsRevision.listenable.value, greaterThan(before));
      expect(calls, greaterThan(0));
      SqlWorkspaceSettingsRevision.listenable.removeListener(listener);
    });

    test('mutating theme settings does not notify SqlWorkspaceSettingsRevision',
        () async {
      var sqlCalls = 0;
      void listener() => sqlCalls++;

      SqlWorkspaceSettingsRevision.listenable.addListener(listener);
      final before = SqlWorkspaceSettingsRevision.listenable.value;
      await AppSettings.instance.setThemeMode(ThemeMode.light);
      expect(SqlWorkspaceSettingsRevision.listenable.value, before);
      expect(sqlCalls, 0);
      SqlWorkspaceSettingsRevision.listenable.removeListener(listener);
    });
  });
}
