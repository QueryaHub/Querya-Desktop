import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/settings/preferences_shortcuts_section.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

void main() {
  Widget buildTestWidget({String searchQuery = ''}) {
    return ShadcnApp(
      home: material.Scaffold(
        body: material.SingleChildScrollView(
          child: material.Padding(
            padding: const material.EdgeInsets.all(16),
            child: PreferencesShortcutsSection(searchQuery: searchQuery),
          ),
        ),
      ),
    );
  }

  group('PreferencesShortcutsSection', () {
    testWidgets('renders all category sections and shortcuts by default', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Check category headers exist
      expect(find.text('SQL Editor'), findsWidgets);
      expect(find.text('Data Grid'), findsWidgets);
      expect(find.text('Navigation & App'), findsWidgets);

      // Check specific shortcut actions exist
      expect(find.text('Execute query / selection'), findsOneWidget);
      expect(find.text('Format SQL statement'), findsOneWidget);
      expect(find.text('Toggle full-screen editor'), findsOneWidget);
      expect(find.text('Auto-fit column width'), findsOneWidget);
      expect(find.text('Revert staged cell changes'), findsOneWidget);
      expect(find.text('Filter by cell value'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
    });

    testWidgets('filters list by tapping category filter chips', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Initially both SQL and Data Grid actions are visible
      expect(find.text('Execute query / selection'), findsOneWidget);
      expect(find.text('Inspect / Edit cell'), findsOneWidget);

      // Tap 'Data Grid' filter pill
      final dataGridChip = find.text('Data Grid').first;
      await tester.tap(dataGridChip);
      await tester.pumpAndSettle();

      // Data Grid actions are visible, SQL Editor actions are hidden
      expect(find.text('Inspect / Edit cell'), findsOneWidget);
      expect(find.text('Auto-fit column width'), findsOneWidget);
      expect(find.text('Execute query / selection'), findsNothing);
      expect(find.text('Format SQL statement'), findsNothing);

      // Tap 'SQL Editor' filter pill
      final sqlChip = find.text('SQL Editor').first;
      await tester.tap(sqlChip);
      await tester.pumpAndSettle();

      // SQL Editor visible, Data Grid hidden
      expect(find.text('Execute query / selection'), findsOneWidget);
      expect(find.text('Format SQL statement'), findsOneWidget);
      expect(find.text('Inspect / Edit cell'), findsNothing);

      // Tap 'All' filter pill
      final allChip = find.text('All').first;
      await tester.tap(allChip);
      await tester.pumpAndSettle();

      // Both restored
      expect(find.text('Execute query / selection'), findsOneWidget);
      expect(find.text('Inspect / Edit cell'), findsOneWidget);
    });

    testWidgets('filters shortcuts dynamically by search query', (tester) async {
      await tester.pumpWidget(buildTestWidget(searchQuery: 'format'));
      await tester.pumpAndSettle();

      expect(find.text('Format SQL statement'), findsOneWidget);
      expect(find.text('Execute query / selection'), findsNothing);
      expect(find.text('Inspect / Edit cell'), findsNothing);
    });

    testWidgets('filters shortcuts by keycap search query', (tester) async {
      await tester.pumpWidget(buildTestWidget(searchQuery: 'F11'));
      await tester.pumpAndSettle();

      expect(find.text('Toggle full-screen editor'), findsOneWidget);
      expect(find.text('Execute query / selection'), findsNothing);
    });

    testWidgets('shows empty state when no shortcuts match search', (tester) async {
      await tester.pumpWidget(buildTestWidget(searchQuery: 'xyzunknown'));
      await tester.pumpAndSettle();

      expect(find.text('No shortcuts match "xyzunknown"'), findsOneWidget);
      expect(find.text('Execute query / selection'), findsNothing);
    });
  });
}
