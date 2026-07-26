import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaDropdownTokens', () {
    test('uses design-system defaults from issue #89', () {
      expect(QueryaDropdownTokens.triggerHeight, 36.0);
      expect(QueryaDropdownTokens.menuAlignmentOffset,
          const material.Offset(0, 4));
      expect(QueryaDropdownTokens.menuMaxHeight, 300.0);
      expect(QueryaDropdownTokens.menuBorderRadius, 6.0);
      expect(QueryaDropdownTokens.fontSize, 14.0);
    });
  });

  group('QueryaDropdown', () {
    testWidgets('builds MenuAnchor with current label and chevron',
        (tester) async {
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
      expect(find.byIcon(material.Icons.keyboard_arrow_down_rounded),
          findsOneWidget);

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

    testWidgets('menu enter uses fade-slide (AnimatedSlide + opacity)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaDropdown<String>(
              value: 'a',
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

      await tester.tap(find.text('Alpha'));
      await tester.pump(); // menu open, enter animation mid-flight
      expect(find.byType(material.AnimatedSlide), findsWidgets);
      expect(find.byType(material.AnimatedOpacity), findsWidgets);
      expect(find.byType(material.AnimatedScale), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('item pick delays MenuAnchor close for exit fade-slide',
        (tester) async {
      var selected = 'a';
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaMotionScope(
            level: QueryaMotionLevel.full,
            child: material.Scaffold(
              body: material.StatefulBuilder(
                builder: (context, setState) {
                  return QueryaDropdown<String>(
                    value: selected,
                    items: const [
                      QueryaDropdownItem(value: 'a', label: 'Alpha'),
                      QueryaDropdownItem(value: 'b', label: 'Beta'),
                    ],
                    onSelected: (v) => setState(() => selected = v ?? selected),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      // Exit starts; overlay still mounted mid-standard duration.
      await tester.pump();
      expect(find.text('Beta'), findsWidgets);
      expect(find.byType(material.AnimatedOpacity), findsWidgets);

      await tester.pump(QueryaMotion.standard);
      await tester.pump(); // close() after delay
      await tester.pumpAndSettle();
      // Menu closed; trigger shows selection.
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('menu anchor constrains width to trigger', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 240,
              child: QueryaDropdown<String>(
                value: 'a',
                expandToParent: true,
                items: const [
                  QueryaDropdownItem(value: 'a', label: 'Alpha'),
                  QueryaDropdownItem(value: 'b', label: 'Beta'),
                ],
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final anchor = tester.widget<material.MenuAnchor>(
        find.byType(material.MenuAnchor),
      );
      expect(anchor.crossAxisUnconstrained, isFalse);
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
