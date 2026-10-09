import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/features/results/charts/quick_chart_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../support/querya_theme_test_shell.dart';

void main() {
  const columns = ['name', 'amount'];
  final rows = [
    ['a', '1'],
    ['b', '2'],
    ['c', '3'],
  ];

  Future<void> pumpView(WidgetTester t, List<String> cols,
      List<List<String>> r) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    await t.pumpWidget(queryaThemeTestShell(child: QuickChartView(columns: cols, rows: r)));
    await t.pump();
  }

  testWidgets('pie shows Top 8 with Other, distinct colours and a legend',
      (t) async {
    final many = [
      for (var i = 1; i <= 30; i++) ['cat$i', '$i'],
    ];
    await pumpView(t, columns, many);
    await t.tap(find.bySemanticsLabel('Pie'));
    await t.pump();

    final pie = t.widget<PieChart>(find.byType(PieChart));
    final sections = pie.data.sections;
    expect(sections.length, ChartData.pieTopN + 1);
    expect(sections.map((s) => s.color).toSet().length, sections.length);
    // The legend names every slice, the tail as Other.
    expect(find.text(ChartData.otherLabel), findsOneWidget);
    expect(find.text('cat30'), findsOneWidget);
  });

  testWidgets('40 long X labels render without overflow', (t) async {
    final long = [
      for (var i = 0; i < 40; i++)
        ['a very long category name number $i for the axis', '${i + 1}'],
    ];
    await t.binding.setSurfaceSize(const Size(600, 500));
    await t.pumpWidget(queryaThemeTestShell(
      child: QuickChartView(columns: const ['label', 'amount'], rows: long),
    ));
    await t.pump();
    expect(find.byType(BarChart), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('shows empty state without numeric column', (t) async {
    await pumpView(t, ['name'], [
      ['a'],
    ]);
    expect(find.text('No numeric column to chart'), findsOneWidget);
  });

  testWidgets('renders bar, line and pie', (t) async {
    await pumpView(t, columns, rows);
    expect(find.byType(BarChart), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Line'));
    await t.pump();
    expect(find.byType(LineChart), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Pie'));
    await t.pump();
    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets('export button saves PNG bytes', (t) async {
    Uint8List? saved;
    await t.binding.setSurfaceSize(const Size(1000, 700));
    await t.pumpWidget(queryaThemeTestShell(child: QuickChartView(
      columns: columns,
      rows: rows,
      onSavePng: (png) async => saved = png,
    )));
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('chart_export')));
    await t.pumpAndSettle();
    await t.tap(find.text('PNG'));
    await t.pump();
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (saved == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pump();
    expect(saved, isNotNull);
    expect(saved!.isNotEmpty, isTrue);
  });

  testWidgets('export SVG button saves an SVG for the current chart type',
      (t) async {
    String? saved;
    await t.binding.setSurfaceSize(const Size(1000, 700));
    await t.pumpWidget(queryaThemeTestShell(child: QuickChartView(
      columns: columns,
      rows: rows,
      onSaveSvg: (svg) async => saved = svg,
    )));
    await t.pump();

    await t.tap(find.byKey(const material.ValueKey('chart_export')));
    await t.pumpAndSettle();
    await t.tap(find.text('SVG'));
    // The export reads its setting first, which is real I/O.
    for (var i = 0; i < 200 && saved == null; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(saved, isNotNull);
    expect(saved, contains('<svg'));
    expect(saved, contains('<title>amount by name</title>'));
    expect('<rect '.allMatches(saved!).length, 1 + rows.length);

    await t.tap(find.bySemanticsLabel('Pie'));
    await t.pump();
    await t.tap(find.byKey(const material.ValueKey('chart_export')));
    await t.pumpAndSettle();
    saved = null;
    await t.tap(find.text('SVG'));
    for (var i = 0; i < 200 && saved == null; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect('<path '.allMatches(saved!).length, rows.length);
  });

  for (final width in [600.0, 1600.0]) {
    testWidgets('the pie lays out without clipping at ${width.toInt()} px',
        (t) async {
      await t.binding.setSurfaceSize(material.Size(width, 700));
      await t.pumpWidget(queryaThemeTestShell(child: QuickChartView(
        columns: columns,
        rows: rows,
      )));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Pie'));
      await t.pump();
      expect(find.byType(PieChart), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
