import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/extensions/extension_table_toolbar.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

void main() {
  group('ExtensionTableToolbar', () {
    testWidgets('renders title, pagination chip, and buttons correctly', (tester) async {
      bool ddlOpened = false;
      bool filterToggled = false;
      bool refreshed = false;
      bool nextClicked = false;
      bool prevClicked = false;

      await tester.pumpWidget(
        material.MaterialApp(
          theme: material.ThemeData.light(),
          home: material.Scaffold(
            body: ShadcnApp(
              home: ExtensionTableToolbar(
                title: 'Table · analytics.events',
                paginationLabel: 'Rows 1–200 of 5,000',
                tableIcon: material.Icons.table_chart_outlined,
                loading: false,
                canGoPrevious: true,
                canGoNext: true,
                filterActive: false,
                filterText: '',
                onToggleFilter: () => filterToggled = true,
                onOpenDdl: () => ddlOpened = true,
                onGoPrevious: () => prevClicked = true,
                onGoNext: () => nextClicked = true,
                onRefresh: () => refreshed = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Table · analytics.events'), findsOneWidget);
      expect(find.text('Rows 1–200 of 5,000'), findsOneWidget);
      expect(find.text('DDL'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.ensureVisible(find.text('DDL'));
      await tester.tap(find.text('DDL'));
      expect(ddlOpened, isTrue);

      await tester.ensureVisible(find.text('Filter'));
      await tester.tap(find.text('Filter'));
      expect(filterToggled, isTrue);

      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'), warnIfMissed: false);
      expect(prevClicked, isTrue);

      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'), warnIfMissed: false);
      expect(nextClicked, isTrue);

      await tester.ensureVisible(find.text('Refresh'));
      await tester.tap(find.text('Refresh'), warnIfMissed: false);
      expect(refreshed, isTrue);
    });

    testWidgets('shows active filter status and disables nav when loading', (tester) async {
      await tester.pumpWidget(
        material.MaterialApp(
          theme: material.ThemeData.light(),
          home: material.Scaffold(
            body: ShadcnApp(
              home: ExtensionTableToolbar(
                title: 'View · analytics.summary',
                paginationLabel: 'Loading data...',
                tableIcon: material.Icons.view_list_rounded,
                loading: true,
                canGoPrevious: false,
                canGoNext: false,
                filterActive: true,
                filterText: 'id > 100',
                onToggleFilter: () {},
                onOpenDdl: () {},
                onGoPrevious: () {},
                onGoNext: () {},
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Filter (active)'), findsOneWidget);
      expect(find.text('Loading data...'), findsOneWidget);
    });
  });
}
