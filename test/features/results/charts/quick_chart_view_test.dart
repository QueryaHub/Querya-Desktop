import 'dart:math' show max, min, sqrt1_2;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/features/results/charts/quick_chart_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../support/querya_theme_test_shell.dart';

void main() {
  // The export reads its theme setting; the tests answer it without the
  // local database, which is shared by test processes in CI.
  setUp(() => AppSettings.exportCurrentThemeOverride = () async => false);
  tearDown(() => AppSettings.exportCurrentThemeOverride = null);

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

  testWidgets('the pie grows with the pane and keeps its radius ratio (#1160)',
      (t) async {
    final widths = <double>[];
    for (final width in [600.0, 1600.0]) {
      await t.binding.setSurfaceSize(material.Size(width, 700));
      await t.pumpWidget(queryaThemeTestShell(
          child: QuickChartView(columns: columns, rows: rows)));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Pie'));
      await t.pump();

      final size = t.getSize(find.byType(PieChart));
      final radius =
          t.widget<PieChart>(find.byType(PieChart)).data.sections.first.radius;
      // Outer radius is 88% of the half side, the hole 45% of it: the slice
      // band is 55% of the outer radius.
      expect(radius, closeTo(size.width / 2 * 0.88 * 0.55, 0.01));
      widths.add(size.width);
    }
    expect(widths[1], greaterThan(widths[0]));
  });

  testWidgets('bar tooltips show the full number on the theme popover (#1161)',
      (t) async {
    await pumpView(t, columns, [
      ['a', '1234567'],
      ['b', '20'],
    ]);
    await t.tap(find.bySemanticsLabel('Bar'));
    await t.pump();

    final tooltip = t
        .widget<BarChart>(find.byType(BarChart))
        .data
        .barTouchData
        .touchTooltipData;
    final group = BarChartGroupData(x: 0, barRods: [
      BarChartRodData(toY: 1234567),
    ]);
    expect(
      tooltip.getTooltipItem(group, 0, group.barRods.first, 0)?.text,
      contains('1,234,567'),
    );
    final popover = Theme.of(t.element(find.byType(BarChart))).colorScheme.popover;
    expect(tooltip.getTooltipColor(group), popover);
  });

  testWidgets('many X labels rotate and reserve room, few do not (#1161)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 700));
    await t.pumpWidget(queryaThemeTestShell(
        child: QuickChartView(
      columns: const ['label', 'value'],
      rows: [
        for (var i = 1; i <= 40; i++) ['a long category label number $i', '$i'],
      ],
    )));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Bar'));
    await t.pump();
    final many = t
        .widget<BarChart>(find.byType(BarChart))
        .data
        .titlesData
        .bottomTitles
        .sideTitles
        .reservedSize;
    expect(many, 52);

    await pumpView(t, columns, rows);
    await t.tap(find.bySemanticsLabel('Bar'));
    await t.pump();
    final few = t
        .widget<BarChart>(find.byType(BarChart))
        .data
        .titlesData
        .bottomTitles
        .sideTitles
        .reservedSize;
    expect(few, 28);
  });

  /// WCAG contrast ratio of two colours.
  double contrast(material.Color a, material.Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  // An imported VS Code theme (GitHub Dark-like colours).
  final imported = buildQueryaThemeFromVsCodeColors(
    brightness: material.Brightness.dark,
    colors: const {
      'editor.background': '#0d1117',
      'editor.foreground': '#c9d1d9',
      'editorWidget.background': '#161b22',
      'editorHoverWidget.background': '#161b22',
      'foreground': '#c9d1d9',
      'widget.border': '#30363d',
    },
  );

  for (final (name, theme) in [
    ('light', QueryaTheme.lightDefault),
    ('dark', QueryaTheme.darkDefault),
    ('imported VS Code', imported),
  ]) {
    testWidgets('$name theme: the bar tooltip is readable (#1161)', (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 700));
      await t.pumpWidget(queryaThemeTestShell(
          data: theme,
          child: QuickChartView(columns: columns, rows: rows)));
      await t.pump();
      await t.tap(find.bySemanticsLabel('Bar'));
      await t.pump();

      final tooltip = t
          .widget<BarChart>(find.byType(BarChart))
          .data
          .barTouchData
          .touchTooltipData;
      final group = BarChartGroupData(x: 0, barRods: [
        BarChartRodData(toY: 3),
      ]);
      final background = tooltip.getTooltipColor(group);
      final text =
          tooltip.getTooltipItem(group, 0, group.barRods.first, 0)!.textStyle.color!;
      final cs = Theme.of(t.element(find.byType(BarChart))).colorScheme;
      expect(background, cs.popover);
      expect(text, cs.popoverForeground);
      // WCAG AA for normal text.
      expect(contrast(background, text), greaterThanOrEqualTo(4.5),
          reason: 'popover $background, text $text');
    });
  }

  testWidgets('40 rotated X labels are spaced so they do not overlap (#1161)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(400, 700));
    await t.pumpWidget(queryaThemeTestShell(
        child: QuickChartView(
      columns: const ['label', 'value'],
      rows: [
        for (var i = 1; i <= 40; i++) ['a long category label number $i', '$i'],
      ],
    )));
    await t.pump();
    await t.tap(find.bySemanticsLabel('Bar'));
    await t.pump();

    final labels = find.textContaining('a long category label number');
    final n = labels.evaluate().length;
    expect(n, inInclusiveRange(2, 8), reason: 'one label per step of five');
    final xs = [for (var i = 0; i < n; i++) t.getCenter(labels.at(i)).dx]
      ..sort();
    final lineHeight = t.getSize(labels.first).height;
    for (var i = 1; i < xs.length; i++) {
      // At 45 degrees two neighbours are (dx * sin 45) apart across the text;
      // more than a line height means they do not overlap.
      expect((xs[i] - xs[i - 1]) * sqrt1_2, greaterThan(lineHeight),
          reason: 'labels $i and ${i - 1}');
    }
  });
}
