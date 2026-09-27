import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

material.Widget _testShell({required material.Widget child}) {
  final td = QueryaTheme.darkDefault
      .toShadcnThemeData()
      .copyWith(platform: () => material.TargetPlatform.linux);
  return ShadcnApp(
    theme: td,
    home: material.Scaffold(
      body: child,
    ),
  );
}

Future<void> _secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('VirtualResultGrid lazy context menu items (#983)', () {
    testWidgets(
        'scrolling and selecting cells does not build context-menu items; opening one does',
        (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name', 'role'],
              rows: List.generate(
                50,
                (i) => ['$i', 'User $i', 'Admin'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final before = gridCellContextMenuItemsBuiltCount;

      // Selecting a cell and scrolling rebuild many cells, but must not
      // build any context-menu item list — that's the whole point of #983.
      await tester.tap(find.text('User 1'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(VirtualResultGrid),
        const material.Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(gridCellContextMenuItemsBuiltCount, before);

      // Right-clicking a cell opens its context menu, which is exactly when
      // the (now lazy) item list must be built.
      await _secondaryClick(tester, find.text('Admin').first);

      expect(gridCellContextMenuItemsBuiltCount, greaterThan(before));
    });
  });
}
