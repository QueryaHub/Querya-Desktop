import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';
import '../helpers/e2e_grid_interactions.dart';

const _timeout = Timeout(Duration(seconds: 60));

/// `pumpAndSettle` never returns while a save runs: the spinner animates.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  // dialect → (quoted table, quoted column)
  const quoting = {
    SqlDialect.postgres: ('"public"."users"', '"name"'),
    SqlDialect.mysql: ('`public`.`users`', '`name`'),
    SqlDialect.sqlite: ('"users"', '"name"'),
  };

  for (final entry in quoting.entries) {
    final dialect = entry.key;
    final (table, column) = entry.value;

    testWidgets('${dialect.name}: UPDATE, INSERT and DELETE are previewed '
        'and committed in one plan', timeout: _timeout, (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(
        tester,
        delegate,
        dialect: dialect,
      );
      await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
      await _frames(tester);

      await E2eGrid.doubleTapCell(tester, 'Alice');
      await E2eGrid.typeAndCommit(tester, 'Alicia');
      await _frames(tester);
      await E2eGrid.tapCell(tester, 'Carol');
      await tester.tap(find.text('Delete Row'));
      await _frames(tester);
      await tester.tap(find.text('Add Row'));
      await _frames(tester);
      E2eGrid.expectStaged(
        state.stagingBuffer!,
        modifiedCells: 1,
        inserted: 1,
        deleted: 1,
      );

      await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyS, ctrl: true);
      await _frames(tester);
      expect(find.text('Confirm Data Changes'), findsOneWidget);
      expect(find.text('TRANSACTION SCRIPT'), findsOneWidget);
      expect(delegate.appliedPlans, isEmpty, reason: 'nothing before confirm');

      await tester.tap(find.text('Apply Changes'));
      await _frames(tester);
      await tester.pump(const Duration(seconds: 6)); // toast timer

      expect(delegate.appliedPlans, hasLength(1));
      final sql = delegate.appliedPlans.single.statements.map((s) => s.sql);
      expect(sql.where((s) => s.startsWith('UPDATE $table SET $column = ')),
          hasLength(1));
      expect(sql.where((s) => s.startsWith('INSERT INTO $table')), hasLength(1));
      expect(sql.where((s) => s.startsWith('DELETE FROM $table')), hasLength(1));
      expect(state.isDirty, isFalse);
    });
  }

  testWidgets('Cancel in the preview keeps every pending edit',
      timeout: _timeout, (tester) async {
    final delegate = FakeTableDataDelegate();
    final state = await pumpGenericTableView(tester, delegate);
    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await _frames(tester);
    await E2eGrid.doubleTapCell(tester, 'Alice');
    await E2eGrid.typeAndCommit(tester, 'Alicia');
    await _frames(tester);

    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyS, ctrl: true);
    await _frames(tester);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    await tester.pump(const Duration(seconds: 6));

    expect(delegate.appliedPlans, isEmpty);
    E2eGrid.expectStaged(state.stagingBuffer!, modifiedCells: 1);
  });
}
