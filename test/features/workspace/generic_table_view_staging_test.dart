import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

void main() {
  group('edit mode', () {
    testWidgets('a table with a primary key can be edited after toggling',
        (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate);

      expect(state.canEdit, isTrue);
      expect(state.editMode, isFalse);

      state.toggleEditMode();
      await tester.pumpAndSettle();

      expect(state.editMode, isTrue);
      expect(state.stagingBuffer, isNotNull);
      expect(state.isDirty, isFalse);
    });

    testWidgets('a read-only session cannot enter edit mode', (tester) async {
      final state = await pumpGenericTableView(
        tester,
        FakeTableDataDelegate(),
        isReadOnly: true,
      );

      expect(state.canEdit, isFalse);
      state.toggleEditMode();
      await tester.pumpAndSettle();
      expect(state.editMode, isFalse);
    });

    testWidgets('views are not editable', (tester) async {
      final state = await pumpGenericTableView(
        tester,
        FakeTableDataDelegate(),
        isView: true,
      );

      expect(state.canEdit, isFalse);
    });

    testWidgets('a table without a primary key is not editable',
        (tester) async {
      final state = await pumpGenericTableView(
        tester,
        FakeTableDataDelegate(primaryKeys: const []),
      );

      expect(state.canEdit, isFalse);
      expect(state.editDisabledReason(), isNotNull);
    });
  });

  group('staging', () {
    testWidgets('edits are buffered and can be reverted', (tester) async {
      final state = await pumpGenericTableView(tester, FakeTableDataDelegate());
      state.toggleEditMode();
      await tester.pumpAndSettle();
      final buffer = state.stagingBuffer!;

      buffer.setCell(0, 1, 'Alicia');
      expect(state.isDirty, isTrue);
      expect(buffer.modifiedCellCount, 1);

      buffer.revertCell(0, 1);
      expect(state.isDirty, isFalse);
    });

    testWidgets('paging is locked while there are unsaved edits',
        (tester) async {
      final state = await pumpGenericTableView(
        tester,
        FakeTableDataDelegate(),
        limit: 2,
      );
      expect(state.canGoNext, isTrue);

      state.toggleEditMode();
      await tester.pumpAndSettle();
      state.stagingBuffer!.setCell(0, 1, 'Alicia');
      await tester.pump();

      expect(state.canGoNext, isFalse);
      expect(state.canGoPrevious, isFalse);
    });
  });

  group('applying changes', () {
    const quoting = {
      SqlDialect.postgres: ('"public"."users"', '"name"'),
      SqlDialect.sqlite: ('"public"."users"', '"name"'),
      SqlDialect.mysql: ('`public`.`users`', '`name`'),
    };

    for (final entry in quoting.entries) {
      final dialect = entry.key;
      final (table, column) = entry.value;

      testWidgets('${dialect.name}: sends a dialect-specific UPDATE',
          (tester) async {
        final delegate = FakeTableDataDelegate();
        final state = await pumpGenericTableView(
          tester,
          delegate,
          dialect: dialect,
        );
        state.toggleEditMode();
        await tester.pumpAndSettle();
        state.stagingBuffer!.setCell(0, 1, 'Alicia');

        final applying = state.applyStagedChanges();
        await tester.pumpAndSettle();
        expect(find.text('Confirm Data Changes'), findsOneWidget);
        await tester.tap(find.text('Apply Changes'));
        await tester.pumpAndSettle();
        await applying;

        expect(delegate.appliedPlans, hasLength(1));
        final plan = delegate.appliedPlans.single;
        expect(plan.dialect, dialect);
        expect(plan.statements, hasLength(1));
        final sql = plan.statements.single.sql;
        expect(sql, startsWith('UPDATE $table SET $column = '));
        expect(sql, contains("'Alicia'"));
        expect(state.isDirty, isFalse, reason: 'buffer is committed');
        expect(state.rows[0][1], 'Alicia');
      });
    }

    testWidgets('cancelling the preview keeps the edits and sends nothing',
        (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate);
      state.toggleEditMode();
      await tester.pumpAndSettle();
      state.stagingBuffer!.setCell(0, 1, 'Alicia');

      final applying = state.applyStagedChanges();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await applying;

      expect(delegate.appliedPlans, isEmpty);
      expect(state.isDirty, isTrue);
      expect(state.isSaving, isFalse);
    });

    testWidgets('a failing save keeps the edits and reports the error',
        (tester) async {
      final delegate = _FailingDelegate();
      final state = await pumpGenericTableView(tester, delegate);
      state.toggleEditMode();
      await tester.pumpAndSettle();
      state.stagingBuffer!.setCell(0, 1, 'Alicia');

      final applying = state.applyStagedChanges();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Changes'));
      await tester.pumpAndSettle();

      expect(
        find.text('No changes were applied. Your edits are still pending.'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await applying;

      expect(state.isDirty, isTrue);
      expect(state.isSaving, isFalse);
    });
  });
}

class _FailingDelegate extends FakeTableDataDelegate {
  @override
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  }) async {
    throw StateError('constraint violated');
  }
}
