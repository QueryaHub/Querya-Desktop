import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/mutation_audit_recorder.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../memory_secrets_backend.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_sql_history_');
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
    testMemorySecrets.clear();
    for (final c in await LocalDb.instance.getConnections()) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
  });

  Future<List<MutationAuditEntry>> waitForAudit(
    int expected, {
    int? connectionId,
  }) async {
    for (var i = 0; i < 40; i++) {
      final list = await LocalDb.instance.listMutationAudit(
        connectionId: connectionId,
      );
      if (list.length >= expected) return list;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return LocalDb.instance.listMutationAudit(connectionId: connectionId);
  }

  group('Mutation audit trail', () {
    setUp(() => LocalDb.instance.clearMutationAudit());

    test('records fields and lists newest first', () async {
      await LocalDb.instance.recordMutationAudit(
        connectionId: 7,
        connectionName: 'orders-prod',
        environment: 'production',
        databaseName: 'shop',
        sqlText: ' UPDATE orders SET paid = true ',
        rowsAffected: 3,
        source: MutationAuditSource.sqlEditor,
      );
      await LocalDb.instance.recordMutationAudit(
        connectionId: 7,
        connectionName: 'orders-prod',
        sqlText: 'DELETE FROM orders WHERE id = 1',
        rowsAffected: 1,
        source: MutationAuditSource.tableEditor,
      );

      final list = await LocalDb.instance.listMutationAudit();
      expect(list.map((e) => e.sqlText), [
        'DELETE FROM orders WHERE id = 1',
        'UPDATE orders SET paid = true',
      ]);
      final update = list.last;
      expect(update.connectionId, 7);
      expect(update.connectionName, 'orders-prod');
      expect(update.environment, 'production');
      expect(update.databaseName, 'shop');
      expect(update.rowsAffected, 3);
      expect(update.source, MutationAuditSource.sqlEditor);
      expect(DateTime.tryParse(update.recordedAt), isNotNull);
      expect(list.first.source, MutationAuditSource.tableEditor);
      expect(list.first.environment, isNull);
      expect(list.first.databaseName, isNull);
    });

    test('filters by connection and respects the limit', () async {
      for (var i = 0; i < 3; i++) {
        await LocalDb.instance.recordMutationAudit(
          connectionId: 1,
          connectionName: 'a',
          sqlText: 'UPDATE t SET a = $i',
          source: MutationAuditSource.sqlEditor,
        );
      }
      await LocalDb.instance.recordMutationAudit(
        connectionId: 2,
        connectionName: 'b',
        sqlText: 'DROP TABLE x',
        source: MutationAuditSource.sqlEditor,
      );

      final onlyB = await LocalDb.instance.listMutationAudit(connectionId: 2);
      expect(onlyB.map((e) => e.sqlText), ['DROP TABLE x']);
      final limited = await LocalDb.instance.listMutationAudit(limit: 2);
      expect(limited, hasLength(2));
      expect(limited.first.sqlText, 'DROP TABLE x');
    });

    test('blank SQL is not recorded', () async {
      await LocalDb.instance.recordMutationAudit(
        connectionName: 'a',
        sqlText: '   ',
        source: MutationAuditSource.sqlEditor,
      );
      expect(await LocalDb.instance.listMutationAudit(), isEmpty);
    });

    test('entries survive removing the connection', () async {
      const row = ConnectionRow(
        type: 'postgres',
        name: 'Temp',
        host: '127.0.0.1',
        port: 5432,
        createdAt: '2026-01-01T00:00:00Z',
      );
      final id = await LocalDb.instance.addConnection(row);
      await LocalDb.instance.recordMutationAudit(
        connectionId: id,
        connectionName: 'Temp',
        sqlText: 'DELETE FROM t',
        source: MutationAuditSource.sqlEditor,
      );
      await LocalDb.instance.removeConnection(id);

      final list = await LocalDb.instance.listMutationAudit();
      expect(list.single.connectionName, 'Temp');
    });

    test('clear removes everything', () async {
      await LocalDb.instance.recordMutationAudit(
        connectionName: 'a',
        sqlText: 'DROP TABLE t',
        source: MutationAuditSource.sqlEditor,
      );
      await LocalDb.instance.clearMutationAudit();
      expect(await LocalDb.instance.listMutationAudit(), isEmpty);
    });
  });

  group('audit recorders', () {
    setUp(() => LocalDb.instance.clearMutationAudit());

    final connection = const ConnectionRow(
      id: 5,
      type: 'postgres',
      name: 'orders-prod',
      host: 'db',
      port: 5432,
      createdAt: '2026-01-01T00:00:00Z',
    ).withEnvironment(ConnectionEnvironment.production);

    test('auditSqlExecution records mutations with environment and rows',
        () async {
      auditSqlExecution(
        connection: connection,
        databaseName: 'shop',
        sql: 'UPDATE orders SET paid = true',
        rowsAffected: 12,
        source: MutationAuditSource.sqlEditor,
      );
      final list = await waitForAudit(1);
      expect(list, hasLength(1));
      expect(list.single.connectionId, 5);
      expect(list.single.environment, 'production');
      expect(list.single.databaseName, 'shop');
      expect(list.single.rowsAffected, 12);
    });

    test('auditSqlExecution ignores reads', () async {
      auditSqlExecution(
        connection: connection,
        sql: 'SELECT * FROM orders',
        source: MutationAuditSource.sqlEditor,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await LocalDb.instance.listMutationAudit(), isEmpty);
    });

    test('auditMutationPlan records one entry per statement', () async {
      const plan = TableMutationPlan(
        dialect: SqlDialect.postgres,
        tableName: 'orders',
        statements: [
          TableMutationStatement(
            type: MutationType.update,
            sql: "UPDATE orders SET status = 'paid' WHERE id = 1",
            description: 'update',
          ),
          TableMutationStatement(
            type: MutationType.delete,
            sql: 'DELETE FROM orders WHERE id = 2',
            description: 'delete',
          ),
        ],
      );
      auditMutationPlan(
        connection: connection,
        databaseName: 'shop',
        plan: plan,
        source: MutationAuditSource.tableEditor,
      );
      final list = await waitForAudit(2);
      expect(list, hasLength(2));
      expect(list.map((e) => e.rowsAffected), [1, 1]);
      expect(list.every((e) => e.source == MutationAuditSource.tableEditor),
          isTrue);
    });
  });
}
