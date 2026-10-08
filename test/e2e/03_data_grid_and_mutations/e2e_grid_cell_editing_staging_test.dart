import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';
import '../helpers/e2e_grid_interactions.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  testWidgets('double click edits a cell, Revert All restores it',
      timeout: _timeout, (tester) async {
    final state = await pumpGenericTableView(tester, FakeTableDataDelegate());

    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await tester.pumpAndSettle();
    expect(state.editMode, isTrue);
    expect(find.text('No changes'), findsOneWidget);

    await E2eGrid.doubleTapCell(tester, 'Bob');
    await E2eGrid.typeAndCommit(tester, 'Bobby');
    await tester.pumpAndSettle();

    E2eGrid.expectStaged(state.stagingBuffer!, modifiedCells: 1);
    expect(find.text('Bobby'), findsOneWidget);
    expect(find.text('No changes'), findsNothing);

    await tester.tap(find.text('Revert All'));
    await tester.pumpAndSettle();

    E2eGrid.expectStaged(state.stagingBuffer!);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Bobby'), findsNothing);
    expect(find.text('No changes'), findsOneWidget);
  });

  testWidgets('Delete Row marks the selected row and Restore Row undoes it',
      timeout: _timeout, (tester) async {
    final state = await pumpGenericTableView(tester, FakeTableDataDelegate());
    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await tester.pumpAndSettle();

    await E2eGrid.tapCell(tester, 'Carol');
    await tester.tap(find.text('Delete Row'));
    await tester.pumpAndSettle();
    E2eGrid.expectStaged(state.stagingBuffer!, deleted: 1);
    expect(find.text('Restore Row'), findsOneWidget);

    await tester.tap(find.text('Restore Row'));
    await tester.pumpAndSettle();
    E2eGrid.expectStaged(state.stagingBuffer!);
    expect(find.text('Delete Row'), findsOneWidget);
  });

  testWidgets('Add Row stages an insert and Revert All drops it',
      timeout: _timeout, (tester) async {
    final state = await pumpGenericTableView(tester, FakeTableDataDelegate());
    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Row'));
    await tester.pumpAndSettle();
    E2eGrid.expectStaged(state.stagingBuffer!, inserted: 1);

    await tester.tap(find.text('Revert All'));
    await tester.pumpAndSettle();
    E2eGrid.expectStaged(state.stagingBuffer!);
  });

  testWidgets('a read-only session never offers editing', timeout: _timeout,
      (tester) async {
    final state = await pumpGenericTableView(
      tester,
      FakeTableDataDelegate(),
      isReadOnly: true,
    );

    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyE, ctrl: true);
    await tester.pumpAndSettle();

    expect(state.editMode, isFalse);
    expect(find.text('Add Row'), findsNothing);
  });
}
