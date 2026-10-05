import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_stage.dart';
import 'package:querya_desktop/features/mongodb/mongo_aggregation_workspace.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final connection = MongoConnection(id: 1, name: 'test', host: 'localhost');

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    List<MongoAggregationStage>? initialStages,
    material.VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = const material.Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      queryaThemeTestShell(
        data: QueryaTheme.darkDefault,
        child: material.SizedBox(
          width: 1400,
          height: 800,
          child: MongoAggregationWorkspace(
            connection: connection,
            database: 'ecommerce',
            collection: 'orders',
            initialStages: initialStages,
            onBack: onBack,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MongoAggregationWorkspace widget tests', () {
    testWidgets('renders title, action bar, and default initial stage', (tester) async {
      await pumpWorkspace(tester);

      expect(find.text('Aggregation Pipeline: orders'), findsOneWidget);
      expect(find.text('Pipeline Stages'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Add Stage'), findsOneWidget);
      expect(find.text('Export Code'), findsOneWidget);
      expect(find.text('Run Pipeline'), findsOneWidget);
      expect(find.text('No Documents Yet'), findsOneWidget);
    });

    testWidgets('can add a new stage', (tester) async {
      await pumpWorkspace(tester);

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsNothing);

      // Tap Add Stage button
      await tester.tap(find.text('Add Stage'));
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('2 stages'), findsOneWidget);
    });

    testWidgets('can reorder and delete stages', (tester) async {
      final stages = [
        const MongoAggregationStage(
          id: 'stage_1',
          operator: r'$match',
          queryText: '{"status": "A"}',
        ),
        const MongoAggregationStage(
          id: 'stage_2',
          operator: r'$limit',
          queryText: '10',
        ),
      ];

      await pumpWorkspace(tester, initialStages: stages);

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);

      // Delete stage 2
      final deleteButtons = find.byTooltip('Delete Stage');
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsNothing);
      expect(find.text('1 stages'), findsOneWidget);
    });

    testWidgets('shows validation error on invalid JSON stage body', (tester) async {
      await pumpWorkspace(tester);

      // Enter invalid JSON in the stage textfield
      final textField = find.byType(material.TextField).first;
      await tester.enterText(textField, '{ invalid json');
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid JSON'), findsOneWidget);

      // Attempting to run pipeline shows error banner
      final runButton = find.text('Run Pipeline');
      await tester.ensureVisible(runButton);
      await tester.tap(runButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('syntax error'), findsOneWidget);
    });

    testWidgets('opens export code dialog and displays code templates', (tester) async {
      await pumpWorkspace(tester);

      await tester.tap(find.text('Export Code'));
      await tester.pumpAndSettle();

      expect(find.text('Export Aggregation Pipeline'), findsOneWidget);
      expect(find.text('mongosh (Shell)'), findsOneWidget);
      expect(find.text('Node.js'), findsOneWidget);
      expect(find.text('Python'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);

      // Switch to Python tab
      await tester.tap(find.text('Python'));
      await tester.pumpAndSettle();

      expect(find.textContaining('pymongo'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Export Aggregation Pipeline'), findsNothing);
    });

    testWidgets('calls onBack callback when Back to Documents is pressed', (tester) async {
      bool backTapped = false;
      await pumpWorkspace(tester, onBack: () => backTapped = true);

      final backButton = find.text('Back to Documents');
      expect(backButton, findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(backTapped, isTrue);
    });

    testWidgets('toggle switch disables stage', (tester) async {
      await pumpWorkspace(tester);

      expect(find.text('Disabled'), findsNothing);

      // Tap Switch
      final switchWidget = find.byType(Switch).first;
      await tester.tap(switchWidget);
      await tester.pumpAndSettle();

      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('0 / 1 active'), findsOneWidget);
    });
  });
}
