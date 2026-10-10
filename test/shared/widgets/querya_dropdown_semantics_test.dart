import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

Widget _dropdown({bool enabled = true}) {
  return queryaThemeTestShell(
    child: QueryaDropdown<String>(
      value: 'b',
      hint: 'Pick one',
      enabled: enabled,
      items: const [
        QueryaDropdownItem(value: 'a', label: 'Alpha'),
        QueryaDropdownItem(value: 'b', label: 'Beta'),
      ],
      onSelected: (_) {},
    ),
  );
}

void main() {
  group('QueryaDropdown semantics (#1371)', () {
    testWidgets('the trigger is a button with the value and hint, collapsed',
        (tester) async {
      await tester.pumpWidget(_dropdown());

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.expanded == false &&
              w.properties.value == 'Beta' &&
              w.properties.hint == 'Pick one',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a disabled dropdown is exposed as disabled', (tester) async {
      await tester.pumpWidget(_dropdown(enabled: false));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.enabled == false &&
              w.properties.value == 'Beta',
        ),
        findsOneWidget,
      );
    });

    testWidgets('open menu reports expanded and marks the selected item',
        (tester) async {
      await tester.pumpWidget(_dropdown());

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.expanded == true,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.selected == true &&
              w.properties.enabled == true,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.selected == false,
        ),
        findsOneWidget,
      );
    });
  });
}
