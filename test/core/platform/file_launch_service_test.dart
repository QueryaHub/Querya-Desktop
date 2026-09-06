import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/sql_editor_command_bridge.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('querya_file_launch_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    FileLaunchService.instance.setPendingTarget(null);
    SqlEditorCommandBridge.instance.resetForTest();
  });

  group('FileLaunchService - detectKind and parseArgument', () {
    test('detects SQL files accurately', () {
      expect(FileLaunchService.detectKind('query.sql'), FileLaunchKind.sql);
      expect(FileLaunchService.detectKind('/path/to/MIGRATION.SQL'), FileLaunchKind.sql);
    });

    test('detects SQLite databases accurately', () {
      expect(FileLaunchService.detectKind('app.db'), FileLaunchKind.sqlite);
      expect(FileLaunchService.detectKind('data.sqlite'), FileLaunchKind.sqlite);
      expect(FileLaunchService.detectKind('analytics.sqlite3'), FileLaunchKind.sqlite);
      expect(FileLaunchService.detectKind('backup.db3'), FileLaunchKind.sqlite);
    });

    test('returns unknown for unsupported extensions', () {
      expect(FileLaunchService.detectKind('doc.txt'), FileLaunchKind.unknown);
      expect(FileLaunchService.detectKind('image.png'), FileLaunchKind.unknown);
      expect(FileLaunchService.detectKind('config.json'), FileLaunchKind.unknown);
    });

    test('parses raw path and ignores flags', () {
      expect(FileLaunchService.parseArgument('-v'), isNull);
      expect(FileLaunchService.parseArgument('--enable-feature=1'), isNull);
      expect(FileLaunchService.parseArgument(''), isNull);

      final target = FileLaunchService.parseArgument('/tmp/test_schema.sql');
      expect(target, isNotNull);
      expect(target!.kind, FileLaunchKind.sql);
      expect(target.fileName, 'test_schema.sql');
    });

    test('parses quoted paths and file:// URIs', () {
      final targetQuoted = FileLaunchService.parseArgument('"/home/user/my database.sqlite"');
      expect(targetQuoted, isNotNull);
      expect(targetQuoted!.kind, FileLaunchKind.sqlite);
      expect(targetQuoted.path, endsWith('my database.sqlite'));

      final targetUri = FileLaunchService.parseArgument('file:///var/data/app.db');
      expect(targetUri, isNotNull);
      expect(targetUri!.kind, FileLaunchKind.sqlite);
      expect(targetUri.fileName, 'app.db');
    });

    test('processes launch arguments array', () {
      FileLaunchService.instance.processLaunchArguments([
        '--window-size=1280,720',
        '/home/user/queries/reporting.sql',
      ]);

      expect(FileLaunchService.instance.hasPendingTarget, isTrue);
      expect(FileLaunchService.instance.pendingTarget?.fileName, 'reporting.sql');
      expect(FileLaunchService.instance.pendingTarget?.kind, FileLaunchKind.sql);

      final consumed = FileLaunchService.instance.consumePendingTarget();
      expect(consumed?.fileName, 'reporting.sql');
      expect(FileLaunchService.instance.hasPendingTarget, isFalse);
    });
  });

  group('FileLaunchService - SQLite registration and SQL reading', () {
    test('resolves or registers sqlite connection in LocalDb', () async {
      final dbFile = File(p.join(tempDir.path, 'users.sqlite'));
      await dbFile.writeAsString('test database content');

      final target = FileLaunchTarget(
        path: dbFile.path,
        kind: FileLaunchKind.sqlite,
      );

      // First resolution should register connection
      final conn1 = await FileLaunchService.instance.resolveOrRegisterSqliteConnection(target);
      expect(conn1.id, isNotNull);
      expect(conn1.type, 'sqlite');
      expect(conn1.host, target.path);
      expect(conn1.name, 'users');

      // Second resolution should find existing connection without creating duplicate
      final conn2 = await FileLaunchService.instance.resolveOrRegisterSqliteConnection(target);
      expect(conn2.id, conn1.id);
      expect(conn2.host, conn1.host);
    });

    test('reads SQL file content properly', () async {
      final sqlFile = File(p.join(tempDir.path, 'script.sql'));
      const sampleSql = 'SELECT * FROM users WHERE active = 1;';
      await sqlFile.writeAsString(sampleSql);

      final target = FileLaunchTarget(
        path: sqlFile.path,
        kind: FileLaunchKind.sql,
      );

      final content = await FileLaunchService.instance.readSqlContent(target);
      expect(content, sampleSql);
    });
  });

  group('SqlEditorCommandBridge - openFileWithContent', () {
    test('delivers file content immediately if registered', () {
      String? deliveredSql;
      String? deliveredPath;
      String? deliveredTitle;

      SqlEditorCommandBridge.instance.register(
        connectionId: 1,
        onNew: () {},
        onOpen: () {},
        onSave: () {},
        onOpenWithContent: (sql, path, title) {
          deliveredSql = sql;
          deliveredPath = path;
          deliveredTitle = title;
        },
      );

      SqlEditorCommandBridge.instance.openFileWithContent(
        sql: 'SELECT 1;',
        filePath: '/tmp/test.sql',
        title: 'test.sql',
      );

      expect(deliveredSql, 'SELECT 1;');
      expect(deliveredPath, '/tmp/test.sql');
      expect(deliveredTitle, 'test.sql');
    });

    test('queues and flushes file content when registered later', () {
      String? deliveredSql;
      String? deliveredTitle;

      // Invoked before registration
      SqlEditorCommandBridge.instance.openFileWithContent(
        sql: 'SELECT 42;',
        filePath: '/tmp/answer.sql',
        title: 'answer.sql',
      );

      expect(deliveredSql, isNull);

      // Now register
      SqlEditorCommandBridge.instance.register(
        connectionId: 1,
        onNew: () {},
        onOpen: () {},
        onSave: () {},
        onOpenWithContent: (sql, path, title) {
          deliveredSql = sql;
          deliveredTitle = title;
        },
      );

      expect(deliveredSql, 'SELECT 42;');
      expect(deliveredTitle, 'answer.sql');
    });
  });
}
