import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/workspace/data_grid_calc_bar.dart';
import 'package:querya_desktop/features/workspace/grid_selection_calc_engine.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardContent;

  setUp(() {
    clipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (message) async {
      if (message.method == 'Clipboard.setData') {
        clipboardContent = (message.arguments as Map)['text'] as String?;
        return null;
      }
      if (message.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardContent};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  material.Widget buildBar(GridCalcStats stats) {
    return queryaThemeTestShell(
      child: material.Scaffold(
        body: material.Column(
          children: [
            const material.Spacer(),
            DataGridCalcBar(stats: stats),
          ],
        ),
      ),
    );
  }

  group('DataGridCalcBar', () {
    const populatedStats = GridCalcStats(
      totalCount: 5,
      distinctCount: 4,
      numericCount: 4,
      nullCount: 1,
      sum: 100.0,
      average: 25.0,
      median: 20.0,
      min: 10.0,
      max: 40.0,
    );

    testWidgets('renders all stat metrics and mono typography', (tester) async {
      await tester.pumpWidget(buildBar(populatedStats));
      await tester.pumpAndSettle();

      expect(find.text('Count: '), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Distinct: '), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('NULLs: '), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Sum: '), findsOneWidget);
      expect(find.text('Avg: '), findsOneWidget);
      expect(find.text('Median: '), findsOneWidget);
      expect(find.text('Min: '), findsOneWidget);
      expect(find.text('Max: '), findsOneWidget);
      expect(find.text('Copy Stats'), findsOneWidget);

      final valText = tester.widget<material.Text>(find.text('5'));
      expect(valText.style?.fontFamily, QueryaTypography.mono);
      expect(
        valText.style?.fontFamilyFallback,
        QueryaTypography.monoFontFamilyFallback,
      );
    });

    testWidgets(
        'collapsing stats does not throw RenderFlex overflow during animation (#1641)',
        (tester) async {
      final statsNotifier = material.ValueNotifier<GridCalcStats>(populatedStats);
      addTearDown(statsNotifier.dispose);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.Column(
              children: [
                const material.Spacer(),
                material.ValueListenableBuilder<GridCalcStats>(
                  valueListenable: statsNotifier,
                  builder: (_, s, __) => DataGridCalcBar(stats: s),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify currently expanded
      expect(find.text('Count: '), findsOneWidget);

      // Collapse to empty stats
      statsNotifier.value = GridCalcStats.empty;
      await tester.pump();

      // Pump partial frames during collapse animation (e.g. at 40ms, 80ms, 120ms, 160ms)
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Now collapsed
      expect(find.text('Count: '), findsNothing);
    });

    testWidgets('copy button copies full stats summary to clipboard',
        (tester) async {
      await tester.pumpWidget(buildBar(populatedStats));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy Stats'));
      await tester.pump();

      expect(clipboardContent, populatedStats.toSummaryString());
    });
  });
}
