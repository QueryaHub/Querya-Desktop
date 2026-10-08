import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 120));
const _rowCount = 50000;

int _builtRows() => find
    .byWidgetPredicate((w) =>
        w.key is material.ValueKey &&
        '${(w.key as material.ValueKey).value}'.startsWith('result-row-'))
    .evaluate()
    .length;

material.ScrollController _verticalController(WidgetTester tester) {
  final scrollable = tester.widget<material.Scrollable>(
    find
        .byWidgetPredicate((w) =>
            w is material.Scrollable && w.axis == material.Axis.vertical)
        .first,
  );
  return scrollable.controller!;
}

void main() {
  Future<dynamic> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rows = List.generate(_rowCount, (i) => ['$i', 'Value $i']);
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 1000,
            height: 600,
            child: VirtualResultGrid(columns: const ['id', 'value'], rows: rows),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(VirtualResultGrid));
  }

  testWidgets('50 000 rows build only what the viewport shows',
      timeout: _timeout, (tester) async {
    await open(tester);

    expect(find.text('Value 0'), findsOneWidget);
    expect(find.text('Value 49999'), findsNothing);
    expect(_builtRows(), lessThan(100));
  });

  testWidgets('fast scrolling keeps the widget count and cache bounded',
      timeout: _timeout, (tester) async {
    final dynamic state = await open(tester);

    for (var i = 0; i < 30; i++) {
      await tester.fling(
        find.byType(VirtualResultGrid),
        const material.Offset(0, -800),
        6000,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_builtRows(), lessThan(100), reason: 'after fling $i');
    }
    await tester.pumpAndSettle();

    expect(find.text('Value 0'), findsNothing);
    expect(state.rowWidgetsCacheCount, lessThanOrEqualTo(200));
  });

  testWidgets('the last row is reachable and scrolling back restores the first',
      timeout: _timeout, (tester) async {
    await open(tester);
    final controller = _verticalController(tester);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Value 49999'), findsOneWidget);
    expect(find.text('Value 0'), findsNothing);
    expect(_builtRows(), lessThan(100));

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Value 0'), findsOneWidget);
    expect(find.text('Value 49999'), findsNothing);
  });
}
