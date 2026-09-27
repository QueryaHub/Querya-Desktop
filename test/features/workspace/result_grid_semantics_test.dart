import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _testShell({required material.Widget child}) {
  return queryaThemeTestShell(
    child: material.Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('VirtualResultGrid semantics (#981)', () {
    testWidgets(
        'each row exposes one semantics node with a header:value label, not one per cell',
        (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'name', 'role'],
              rows: [
                ['1', 'Alice', 'Admin'],
                ['2', 'Bob', 'User'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Row 1, id: 1, name: Alice, role: Admin'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Row 2, id: 2, name: Bob, role: User'),
        findsOneWidget,
      );

      // Cells no longer contribute their own semantics nodes (gesture/tooltip
      // node per cell was the ~17ms-per-result-set cost this issue is about):
      // the plain cell text must not appear as its own semantics label.
      expect(find.bySemanticsLabel('Alice'), findsNothing);
      expect(find.bySemanticsLabel('Admin'), findsNothing);

      handle.dispose();
    });

    testWidgets('a cell being edited keeps its own (text field) semantics',
        (tester) async {
      final handle = tester.ensureSemantics();

      final buffer = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: const [
          ['1', 'Alice'],
        ],
        primaryKeys: const ['id'],
      );
      addTearDown(buffer.dispose);

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Alice'],
              ],
              stagingBuffer: buffer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select the cell, then enter edit mode the same way a real user does
      // (VirtualResultGrid only starts editing via F2/Enter/Space on a
      // selected cell, not via tap/double-tap — see #991).
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(material.EditableText), findsOneWidget);

      handle.dispose();
    });
  });
}
