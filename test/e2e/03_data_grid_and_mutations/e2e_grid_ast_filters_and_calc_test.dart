import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';
import '../helpers/e2e_grid_interactions.dart';

const _timeout = Timeout(Duration(seconds: 60));

FakeTableDataDelegate _accounts() => FakeTableDataDelegate(
      columns: const ['id', 'name', 'balance'],
      rows: const [
        ['1', 'alice', '150.00'],
        ['2', 'bob', '50.00'],
        ['3', 'charlie', '300.00'],
        ['4', 'david', '0.00'],
      ],
    );

Future<void> _filter(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(DataGridFilterBar),
      matching: find.byType(material.TextField),
    ),
    text,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('balance > 100 keeps only the matching rows', timeout: _timeout,
      (tester) async {
    await pumpGenericTableView(tester, _accounts());
    await tester.tap(find.byTooltip('Toggle Quick Filter'));
    await tester.pumpAndSettle();

    await _filter(tester, 'balance > 100');

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('charlie'), findsOneWidget);
    expect(find.text('bob'), findsNothing);
    expect(find.text('david'), findsNothing);
    expect(find.text('2 / 4'), findsOneWidget);

    await _filter(tester, '');
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('david'), findsOneWidget);
  });

  testWidgets('a comparison on a missing column matches nothing harmful',
      timeout: _timeout, (tester) async {
    await pumpGenericTableView(tester, _accounts());
    await tester.tap(find.byTooltip('Toggle Quick Filter'));
    await tester.pumpAndSettle();

    await _filter(tester, 'bob');
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('alice'), findsNothing);
  });

  testWidgets('selecting a numeric cell shows its Quick Calc statistics',
      timeout: _timeout, (tester) async {
    await pumpGenericTableView(tester, _accounts());

    await E2eGrid.tapCell(tester, '300.00');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Count: '), findsOneWidget);
    expect(find.text('Sum: '), findsOneWidget);
    expect(find.text('Max: '), findsOneWidget);
  });
}
