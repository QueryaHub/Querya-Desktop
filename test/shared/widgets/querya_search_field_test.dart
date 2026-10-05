import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaSearchField', () {
    testWidgets('renders placeholder and search icon', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaSearchField(
            placeholder: 'Filter collections...',
          ),
        ),
      );

      expect(find.text('Filter collections...'), findsOneWidget);
      expect(find.byIcon(material.Icons.search_rounded), findsOneWidget);
    });

    testWidgets('shows clear button and invokes clear', (tester) async {
      final controller = material.TextEditingController(text: 'users');
      String? changedValue;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaSearchField(
            controller: controller,
            debounceDuration: Duration.zero,
            onChanged: (val) => changedValue = val,
          ),
        ),
      );

      final clearBtn = find.byIcon(material.Icons.close_rounded);
      expect(clearBtn, findsOneWidget);

      await tester.tap(clearBtn);
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(changedValue, isEmpty);
      expect(find.byIcon(material.Icons.close_rounded), findsNothing);
    });

    testWidgets('invokes onChanged with debounce', (tester) async {
      String? searchResult;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaSearchField(
            debounceDuration: const Duration(milliseconds: 100),
            onChanged: (val) => searchResult = val,
          ),
        ),
      );

      await tester.enterText(find.byType(material.TextField), 'query');
      expect(searchResult, isNull);

      await tester.pump(const Duration(milliseconds: 150));
      expect(searchResult, 'query');
    });
  });
}
