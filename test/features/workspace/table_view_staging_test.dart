import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('tableViewEditingEnabled', () {
    test('true only for base tables with a primary key', () {
      expect(
        tableViewEditingEnabled(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: true,
        ),
        isTrue,
      );
    });

    test('false for views, materialized views, custom SQL, and missing PK', () {
      expect(
        tableViewEditingEnabled(
          isView: true,
          customSqlActive: false,
          hasPrimaryKey: true,
        ),
        isFalse,
      );
      expect(
        tableViewEditingEnabled(
          isView: false,
          isMaterializedView: true,
          customSqlActive: false,
          hasPrimaryKey: true,
        ),
        isFalse,
      );
      expect(
        tableViewEditingEnabled(
          isView: false,
          customSqlActive: true,
          hasPrimaryKey: true,
        ),
        isFalse,
      );
      expect(
        tableViewEditingEnabled(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: false,
        ),
        isFalse,
      );
    });
  });

  group('tableViewEditDisabledReason', () {
    test('explains views, custom SQL, and missing PK', () {
      expect(
        tableViewEditDisabledReason(
          isView: true,
          customSqlActive: false,
          hasPrimaryKey: true,
          schemaLoaded: true,
        ),
        'Views are read-only',
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          isMaterializedView: true,
          customSqlActive: false,
          hasPrimaryKey: true,
          schemaLoaded: true,
        ),
        'Views are read-only',
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          customSqlActive: true,
          hasPrimaryKey: true,
          schemaLoaded: true,
        ),
        'Custom SQL results are read-only',
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: false,
          schemaLoaded: true,
        ),
        'Cannot edit: no primary key detected',
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: false,
          schemaLoaded: false,
        ),
        isNull,
      );
      expect(
        tableViewEditDisabledReason(
          isView: false,
          customSqlActive: false,
          hasPrimaryKey: true,
          schemaLoaded: true,
        ),
        isNull,
      );
    });
  });

  group('columnDataTypesFromSchema', () {
    test('maps column names to types and skips empty types', () {
      const schema = TableSchemaMeta(
        tableName: 'users',
        columns: [
          TableColumnMeta(name: 'id', dataType: 'integer'),
          TableColumnMeta(name: 'name', dataType: 'text'),
          TableColumnMeta(name: 'skip', dataType: ''),
        ],
      );
      expect(
        columnDataTypesFromSchema(schema),
        {'id': 'integer', 'name': 'text'},
      );
    });

    test('columnMetaFromSchema indexes columns by name', () {
      const schema = TableSchemaMeta(
        tableName: 'users',
        columns: [
          TableColumnMeta(
            name: 'id',
            dataType: 'integer',
            omitOnInsert: true,
          ),
        ],
      );
      expect(columnMetaFromSchema(schema)['id']?.omitOnInsert, isTrue);
    });
  });

  group('replaceTableViewStagingBuffer', () {
    test('disposes previous and returns null when editing is disabled', () {
      final previous = DataGridStagingBuffer(
        columns: ['id'],
        rows: [
          ['1'],
        ],
      );
      final next = replaceTableViewStagingBuffer(
        previous: previous,
        columns: ['id'],
        rows: [
          ['1'],
        ],
        enabled: false,
      );
      expect(next, isNull);
      expect(previous.isDirty, isFalse);
    });

    test('creates a buffer when enabled', () {
      final next = replaceTableViewStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Ada'],
        ],
        enabled: true,
      );
      expect(next, isNotNull);
      expect(next!.columns, ['id', 'name']);
      expect(next.originalRows, [
        ['1', 'Ada'],
      ]);
      next.dispose();
    });
  });

  group('applyTableViewStagedChanges', () {
    testWidgets('returns noop when the buffer is clean', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: const material.Scaffold(body: material.SizedBox()),
        ),
      );
      final ctx = tester.element(find.byType(material.Scaffold));
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Ada'],
        ],
      );
      addTearDown(buffer.dispose);

      var executed = false;
      final outcome = await applyTableViewStagedChanges(
        context: ctx,
        buffer: buffer,
        dialect: SqlDialect.postgres,
        tableName: 'users',
        schema: 'public',
        primaryKeys: ['id'],
        execute: (_) async => executed = true,
      );

      expect(outcome.status, TableViewApplyStatus.noop);
      expect(executed, isFalse);
    });

    testWidgets('returns failed when dirty but no primary key', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: const material.Scaffold(body: material.SizedBox()),
        ),
      );
      final ctx = tester.element(find.byType(material.Scaffold));
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Ada'],
        ],
      );
      buffer.setCell(0, 1, 'Grace');
      addTearDown(buffer.dispose);

      var executed = false;
      final outcome = await applyTableViewStagedChanges(
        context: ctx,
        buffer: buffer,
        dialect: SqlDialect.postgres,
        tableName: 'users',
        primaryKeys: const [],
        execute: (_) async => executed = true,
      );

      expect(outcome.isFailed, isTrue);
      expect(outcome.error.toString(), contains('no primary key'));
      expect(executed, isFalse);
    });

    testWidgets('0-row DML is failed and the staging buffer stays dirty',
        (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: const material.Scaffold(body: material.SizedBox()),
        ),
      );
      final ctx = tester.element(find.byType(material.Scaffold));
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Ada'],
        ],
      );
      buffer.setCell(0, 1, 'Grace');
      addTearDown(buffer.dispose);

      final future = applyTableViewStagedChanges(
        context: ctx,
        buffer: buffer,
        dialect: SqlDialect.postgres,
        tableName: 'users',
        schema: 'public',
        primaryKeys: ['id'],
        execute: (_) async => expectDmlMatchedRows(0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Changes'));
      final outcome = await future;

      expect(outcome.isFailed, isTrue);
      expect(outcome.error.toString(), contains('matched 0 rows'));
      expect(buffer.isDirty, isTrue);
    });
  });

  group('expectDmlMatchedRows', () {
    test('allows 1+ affected rows', () {
      expect(() => expectDmlMatchedRows(1), returnsNormally);
      expect(() => expectDmlMatchedRows(3), returnsNormally);
    });

    test('throws on 0-row DML so Save is a failure', () {
      expect(
        () => expectDmlMatchedRows(0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('matched 0 rows'),
          ),
        ),
      );
    });
  });

  group('TableBrowserPendingActions', () {
    testWidgets('shows pending badge and Save when dirty', (tester) async {
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Ada'],
        ],
      );
      addTearDown(buffer.dispose);
      buffer.setCell(0, 1, 'Grace');

      var saved = false;
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: material.Scaffold(
            body: TableBrowserPendingActions(
              buffer: buffer,
              onSave: () => saved = true,
              isSaving: false,
            ),
          ),
        ),
      );

      expect(find.text('1 pending change'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Revert'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(saved, isTrue);

      await tester.tap(find.text('Revert'));
      await tester.pump();
      expect(buffer.isDirty, isFalse);
      expect(find.text('1 pending change'), findsNothing);
    });
  });

  group('confirmDiscardTableEditsIfDirty', () {
    testWidgets('returns true immediately when clean', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          home: const material.Scaffold(body: material.SizedBox()),
        ),
      );
      final ctx = tester.element(find.byType(material.Scaffold));
      final buffer = DataGridStagingBuffer(
        columns: ['id'],
        rows: [
          ['1'],
        ],
      );
      addTearDown(buffer.dispose);

      final ok = await confirmDiscardTableEditsIfDirty(
        context: ctx,
        buffer: buffer,
        tableTitle: 'public.users',
      );
      expect(ok, isTrue);
    });
  });
}
