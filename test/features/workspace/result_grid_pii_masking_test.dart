import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/pii_masking_controller.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

const _columns = ['id', 'email', 'name', 'password'];
const _rows = [
  ['1', 'alice@example.com', 'Alice', 'hunter2'],
  ['2', 'bob@example.com', 'Bob', 'NULL'],
];

void main() {
  tearDown(() => PiiMaskingController.instance.enabled = false);

  Future<void> pump(
    WidgetTester tester, {
    void Function(List<String>)? onSelection,
    void Function(String, String, int)? onFocused,
  }) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: material.SizedBox(
            width: 900,
            height: 400,
            child: VirtualResultGrid(
              columns: _columns,
              rows: _rows,
              onSelectionValuesChanged: onSelection,
              onCellFocused: onFocused,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('values are shown as they are while masking is off',
      (tester) async {
    await pump(tester);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('hunter2'), findsOneWidget);
  });

  testWidgets('turning masking on hides sensitive columns at once',
      (tester) async {
    await pump(tester);

    PiiMaskingController.instance.enabled = true;
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsNothing);
    expect(find.text('al***@example.com'), findsOneWidget);
    expect(find.text('b***@example.com'), findsNothing);
    expect(find.text('bo***@example.com'), findsOneWidget);
    expect(find.text('hunter2'), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
    // Other columns and NULLs are untouched.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('NULL'), findsOneWidget);
  });

  testWidgets('turning masking off restores the values', (tester) async {
    await pump(tester);
    PiiMaskingController.instance.enabled = true;
    await tester.pumpAndSettle();
    PiiMaskingController.instance.enabled = false;
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('hunter2'), findsOneWidget);
  });

  testWidgets('selection callbacks receive masked values', (tester) async {
    List<String>? selected;
    String? focusedValue;
    await pump(
      tester,
      onSelection: (v) => selected = v,
      onFocused: (_, value, __) => focusedValue = value,
    );
    PiiMaskingController.instance.enabled = true;
    await tester.pumpAndSettle();

    await tester.tap(find.text('al***@example.com'));
    await tester.pumpAndSettle();

    expect(selected, ['al***@example.com']);
    expect(focusedValue, 'al***@example.com');
  });

  testWidgets('already selected cells are re-reported when masking toggles',
      (tester) async {
    List<String>? selected;
    await pump(tester, onSelection: (v) => selected = v);

    await tester.tap(find.text('alice@example.com'));
    await tester.pumpAndSettle();
    expect(selected, ['alice@example.com']);

    PiiMaskingController.instance.enabled = true;
    await tester.pumpAndSettle();
    expect(selected, ['al***@example.com']);
  });
}
