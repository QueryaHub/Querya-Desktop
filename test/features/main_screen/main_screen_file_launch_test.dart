import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';

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
    tempDir = await Directory.systemTemp.createTemp('querya_main_screen_file_launch_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    FileLaunchService.instance.setPendingTarget(null);
    SqlEditorCommandBridge.instance.resetForTest();
  });

  tearDown(() async {
    FileLaunchService.instance.setPendingTarget(null);
    SqlEditorCommandBridge.instance.resetForTest();
  });

  group('MainScreen File Launch Handling', () {
    test('resolves SQLite file and prepares workspace state', () async {
      final dbFile = File(p.join(tempDir.path, 'invoices.sqlite'));
      await dbFile.writeAsString('sqlite data placeholder');

      final target = FileLaunchTarget(path: dbFile.path, kind: FileLaunchKind.sqlite);
      FileLaunchService.instance.setPendingTarget(target);

      expect(FileLaunchService.instance.hasPendingTarget, isTrue);

      final consumed = FileLaunchService.instance.consumePendingTarget();
      expect(consumed, isNotNull);

      final conn = await FileLaunchService.instance.resolveOrRegisterSqliteConnection(consumed!);
      expect(conn.type, 'sqlite');
      expect(conn.name, 'invoices');
      expect(conn.host, dbFile.path);

      var workspace = MainScreenWorkspaceState.empty;
      workspace = workspace.selectConnection(conn).openSqliteSqlWorkspace(conn);

      expect(workspace.activeConnection?.name, 'invoices');
      expect(workspace.sqliteSqlTabRequestToken, greaterThan(0));
    });

    test('opens SQL script with existing connection and delivers via bridge', () async {
      final sqlFile = File(p.join(tempDir.path, 'analytics.sql'));
      const scriptContent = 'SELECT count(*) FROM events;';
      await sqlFile.writeAsString(scriptContent);

      final target = FileLaunchTarget(path: sqlFile.path, kind: FileLaunchKind.sql);
      FileLaunchService.instance.setPendingTarget(target);

      final consumed = FileLaunchService.instance.consumePendingTarget();
      expect(consumed, isNotNull);

      final sql = await FileLaunchService.instance.readSqlContent(consumed!);
      expect(sql, scriptContent);

      String? deliveredSql;
      String? deliveredPath;
      String? deliveredTitle;

      SqlEditorCommandBridge.instance.openFileWithContent(
        sql: sql,
        filePath: consumed.path,
        title: consumed.fileName,
      );

      // Register workspace listener to receive queued content
      SqlEditorCommandBridge.instance.register(
        connectionId: 1,
        onNew: () {},
        onOpen: () {},
        onSave: () {},
        onOpenWithContent: (s, path, title) {
          deliveredSql = s;
          deliveredPath = path;
          deliveredTitle = title;
        },
      );

      expect(deliveredSql, scriptContent);
      expect(deliveredPath, sqlFile.path);
      expect(deliveredTitle, 'analytics.sql');
    });

    test('opens SQL script with scratch connection when no connections exist', () async {
      final sqlFile = File(p.join(tempDir.path, 'scratch.sql'));
      const scriptContent = 'SELECT 1;';
      await sqlFile.writeAsString(scriptContent);

      final target = FileLaunchTarget(path: sqlFile.path, kind: FileLaunchKind.sql);
      final sql = await FileLaunchService.instance.readSqlContent(target);

      final scratchRow = ConnectionRow(
        name: 'Local Scratch (${target.fileName})',
        type: 'sqlite',
        host: '',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      final id = await LocalDb.instance.addConnection(scratchRow);
      final conn = scratchRow.copyWith(id: id);

      expect(conn.id, isNotNull);
      expect(conn.name, 'Local Scratch (scratch.sql)');

      var workspace = MainScreenWorkspaceState.empty;
      workspace = workspace.selectConnection(conn).openSqliteSqlWorkspace(conn);
      expect(workspace.activeConnection?.name, contains('scratch.sql'));
      expect(sql, scriptContent);
    });
  });
}
