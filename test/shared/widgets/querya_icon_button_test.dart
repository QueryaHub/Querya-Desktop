import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaIconButton', () {
    testWidgets('renders icon and triggers onPressed', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaIconButton(
            icon: const material.Icon(material.Icons.play_arrow),
            tooltip: 'Run Query',
            onPressed: () => pressed = true,
          ),
        ),
      );

      expect(find.byIcon(material.Icons.play_arrow), findsOneWidget);
      expect(find.byType(material.Tooltip), findsOneWidget);

      await tester.tap(find.byIcon(material.Icons.play_arrow));
      expect(pressed, isTrue);
    });

    testWidgets('respects dense density preset (28px)', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaIconButton(
            icon: material.Icon(material.Icons.refresh),
            density: QueryaIconButtonDensity.dense,
          ),
        ),
      );

      final box = tester.widget<material.SizedBox>(
        find.ancestor(
          of: find.byIcon(material.Icons.refresh),
          matching: find.byType(material.SizedBox),
        ),
      );

      expect(box.width, 28);
      expect(box.height, 28);
    });

    testWidgets('respects standard density preset (32px)', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaIconButton(
            icon: material.Icon(material.Icons.refresh),
            density: QueryaIconButtonDensity.standard,
          ),
        ),
      );

      final box = tester.widget<material.SizedBox>(
        find.ancestor(
          of: find.byIcon(material.Icons.refresh),
          matching: find.byType(material.SizedBox),
        ),
      );

      expect(box.width, 32);
      expect(box.height, 32);
    });

    testWidgets('draws a 2px focus ring while it has keyboard focus (#1370)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaIconButton(
            icon: const material.Icon(material.Icons.refresh),
            onPressed: () {},
          ),
        ),
      );

      final materialFinder = find
          .descendant(
            of: find.byType(QueryaIconButton),
            matching: find.byType(material.Material),
          )
          .first;
      final inkFinder = find.descendant(
        of: find.byType(QueryaIconButton),
        matching: find.byType(material.InkWell),
      );
      double ringWidth() {
        final shape =
            tester.widget<material.Material>(materialFinder).shape!
                as material.RoundedRectangleBorder;
        return shape.side.width;
      }

      expect(ringWidth(), 0);

      tester.widget<material.InkWell>(inkFinder).onFocusChange!(true);
      await tester.pump();
      expect(ringWidth(), 2);

      tester.widget<material.InkWell>(inkFinder).onFocusChange!(false);
      await tester.pump();
      expect(ringWidth(), 0);
    });

    testWidgets('exposes button, enabled and selected state (#1370)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaIconButton(
            icon: const material.Icon(material.Icons.wrap_text),
            tooltip: 'Word wrap',
            isActive: true,
            onPressed: () {},
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.enabled == true &&
              w.properties.selected == true,
        ),
        findsWidgets,
      );
    });

    testWidgets('a button without a callback is exposed as disabled (#1370)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaIconButton(
            icon: material.Icon(material.Icons.refresh),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.enabled == false,
        ),
        findsWidgets,
      );
    });
  });

  group('QueryaToolbarButton', () {
    testWidgets('renders label, icon, shortcut hint, and handles tap', (tester) async {
      var clicked = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaToolbarButton(
            label: 'Filter',
            icon: const material.Icon(material.Icons.filter_list),
            shortcutHint: 'Ctrl+F',
            onPressed: () => clicked = true,
          ),
        ),
      );

      expect(find.text('Filter'), findsOneWidget);
      expect(find.byIcon(material.Icons.filter_list), findsOneWidget);
      expect(find.text('Ctrl+F'), findsOneWidget);

      await tester.tap(find.text('Filter'));
      expect(clicked, isTrue);
    });
  });
}
