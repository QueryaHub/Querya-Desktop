import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaEmptyState', () {
    testWidgets('renders title, description, icon, and handles action', (tester) async {
      var actionFired = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaEmptyState(
            title: 'No collections found',
            description: 'Try adjusting your search filter or create a new collection.',
            icon: const material.Icon(material.Icons.folder_open_rounded),
            actionLabel: 'Create Collection',
            onAction: () => actionFired = true,
          ),
        ),
      );

      expect(find.text('No collections found'), findsOneWidget);
      expect(
        find.text('Try adjusting your search filter or create a new collection.'),
        findsOneWidget,
      );
      expect(find.byIcon(material.Icons.folder_open_rounded), findsOneWidget);
      expect(find.text('Create Collection'), findsOneWidget);

      await tester.tap(find.text('Create Collection'));
      expect(actionFired, isTrue);
    });

    testWidgets('renders properly in compact mode', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaEmptyState(
            title: 'No matches',
            compact: true,
          ),
        ),
      );

      expect(find.text('No matches'), findsOneWidget);
    });
  });
}
