import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaActionButton', () {
    testWidgets('shows label and icon and reports taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(queryaThemeTestShell(
        child: QueryaActionButton(
          label: 'Explain',
          icon: material.Icons.account_tree_outlined,
          onPressed: () => taps++,
        ),
      ));

      expect(find.text('Explain'), findsOneWidget);
      expect(find.byIcon(material.Icons.account_tree_outlined), findsOneWidget);
      await tester.tap(find.text('Explain'));
      expect(taps, 1);
    });

    testWidgets('onPressed null disables the button', (tester) async {
      await tester.pumpWidget(queryaThemeTestShell(
        child: const QueryaActionButton(label: 'Begin'),
      ));

      final button = tester.widget<OutlineButton>(find.byType(OutlineButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('loading swaps the icon for a spinner and disables taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(queryaThemeTestShell(
        child: QueryaActionButton(
          label: 'Execute',
          icon: material.Icons.play_arrow_rounded,
          loading: true,
          onPressed: () => taps++,
        ),
      ));

      expect(find.byType(QueryaSpinner), findsOneWidget);
      expect(find.byIcon(material.Icons.play_arrow_rounded), findsNothing);
      await tester.tap(find.text('Execute'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('destructive tone colors the label', (tester) async {
      await tester.pumpWidget(queryaThemeTestShell(
        child: QueryaActionButton(
          label: 'Cancel',
          icon: material.Icons.stop_rounded,
          isDestructive: true,
          onPressed: () {},
        ),
      ));

      final text = tester.widget<Text>(find.text('Cancel'));
      expect(text.style?.color, isNotNull);
    });

    testWidgets('tooltip wraps the button', (tester) async {
      await tester.pumpWidget(queryaThemeTestShell(
        child: QueryaActionButton(
          label: 'Explain',
          tooltip: 'Show the query plan',
          onPressed: () {},
        ),
      ));

      final tip = tester.widget<material.Tooltip>(find.byType(material.Tooltip));
      expect(tip.message, 'Show the query plan');
    });
  });
}
