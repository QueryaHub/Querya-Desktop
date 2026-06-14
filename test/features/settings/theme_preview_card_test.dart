import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/settings/theme_preview_card.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('ThemePreviewCard', () {
    testWidgets('shows placeholder when no theme is provided', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ThemePreviewCard(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hover a theme to preview.'), findsOneWidget);
    });

    testWidgets('renders preview swatches and sample text from QueryaTheme',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ThemePreviewCard(
              theme: QueryaTheme.darkDefault,
              label: 'Querya Dark',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Querya Dark'), findsOneWidget);
      expect(find.text('Sample text'), findsOneWidget);
      expect(find.text('Bg'), findsOneWidget);
      expect(find.text('Surface'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Accent'), findsOneWidget);
    });

    testWidgets('shows loading state', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ThemePreviewCard(isLoading: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading preview…'), findsOneWidget);
      expect(find.byType(material.CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows non-blocking error message', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ThemePreviewCard(errorMessage: 'Theme file is invalid'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Theme file is invalid'), findsOneWidget);
    });
  });
}
