import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaDropdownTokens', () {
    test('uses design-system defaults from issue #89', () {
      expect(QueryaDropdownTokens.triggerHeight, 32.0);
      expect(QueryaDropdownTokens.menuAlignmentOffset, const material.Offset(0, 4));
      expect(QueryaDropdownTokens.menuMaxHeight, 300.0);
      expect(QueryaDropdownTokens.menuBorderRadius, 6.0);
      expect(QueryaDropdownTokens.fontSize, 13.0);
    });
  });

  group('QueryaDropdown', () {
    testWidgets('builds MenuAnchor with current label and chevron', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaDropdown<String>(
              value: 'b',
              items: const [
                QueryaDropdownItem(value: 'a', label: 'Alpha'),
                QueryaDropdownItem(value: 'b', label: 'Beta'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(material.MenuAnchor), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byIcon(material.Icons.keyboard_arrow_down_rounded), findsOneWidget);

      final box = tester.getSize(find.byType(material.AnimatedContainer).first);
      expect(box.height, QueryaDropdownTokens.triggerHeight);
    });

    testWidgets('opens menu and reports selection', (tester) async {
      int? picked;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaDropdown<int>(
              value: 1,
              items: const [
                QueryaDropdownItem(value: 1, label: 'One'),
                QueryaDropdownItem(value: 2, label: 'Two'),
              ],
              onSelected: (v) => picked = v,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();

      expect(picked, 2);
    });

    testWidgets('shows check on selected menu item', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaDropdown<String>(
              value: 'b',
              items: const [
                QueryaDropdownItem(value: 'a', label: 'Alpha'),
                QueryaDropdownItem(value: 'b', label: 'Beta'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shows hint when value is null', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaDropdown<String?>(
              value: null,
              hint: 'Pick one',
              items: const [
                QueryaDropdownItem<String?>(value: 'x', label: 'X'),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Pick one'), findsOneWidget);
    });
  });
}
