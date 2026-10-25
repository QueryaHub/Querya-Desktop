import 'package:flutter/material.dart' as material;
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/connections/querya_connection_tree_row.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaConnectionTreeRow', () {
    testWidgets(
        'an expandable row is one labelled node that a semantics tap opens '
        '(#1822)', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: QueryaConnectionTreeRow(
              label: 'querya',
              expanded: false,
              onTap: () => taps++,
              textStyle: const material.TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(find.text('querya'));
      expect(node.label, 'querya');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(node.getSemanticsData().flagsCollection.isExpanded, Tristate.isFalse);
      tester.binding.pipelineOwner.semanticsOwner!
          .performAction(node.id, SemanticsAction.tap);
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('renders pinned star icon with workbench.warning (#1643)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.darkDefault,
          child: const material.Material(
            child: QueryaConnectionTreeRow(
              label: 'Production DB',
              isPinned: true,
              textStyle: material.TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final starIconFinder = find.byIcon(material.Icons.star_rounded);
      expect(starIconFinder, findsOneWidget);

      final starIcon = tester.widget<material.Icon>(starIconFinder);
      expect(starIcon.color, QueryaTheme.darkDefault.workbench.warning);
    });

    testWidgets('adapts pinned star icon to light theme workbench.warning (#1643)',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.lightDefault,
          child: const material.Material(
            child: QueryaConnectionTreeRow(
              label: 'Staging DB',
              isPinned: true,
              textStyle: material.TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final starIconFinder = find.byIcon(material.Icons.star_rounded);
      expect(starIconFinder, findsOneWidget);

      final starIcon = tester.widget<material.Icon>(starIconFinder);
      expect(starIcon.color, QueryaTheme.lightDefault.workbench.warning);
    });
  });
}
