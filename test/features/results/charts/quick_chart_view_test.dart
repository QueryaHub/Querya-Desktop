import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('shows empty state without numeric column', (t) async {
    await pumpView(t, ['name'], [
      ['a'],
    ]);
    expect(find.text('No numeric column to chart'), findsOneWidget);
  });

  testWidgets('renders bar, line and pie', (t) async {
    await pumpView(t, columns, rows);
    expect(find.byType(BarChart), findsOneWidget);
    await t.tap(find.text('Line'));
    await t.pump();
    expect(find.byType(LineChart), findsOneWidget);
    await t.tap(find.text('Pie'));
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
    await t.runAsync(() async {
      await t.tap(find.byKey(const material.ValueKey('chart_export')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pump();
    expect(saved, isNotNull);
    expect(saved!.isNotEmpty, isTrue);
  });
}
