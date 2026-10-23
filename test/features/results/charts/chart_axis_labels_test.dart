import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_axis_labels.dart';

void main() {
  // 6 px per character, 13 px line.
  double measure(String t) => t.length * 6.0;
  XLabelPlan plan(List<String> labels, double plotWidth) =>
      ChartAxisLabels.planX(
        labels: labels,
        plotWidth: plotWidth,
        measure: measure,
        lineHeight: 13,
      );

  test('short labels stay on one line, all of them', () {
    final p = plan(['Jan', 'Feb', 'Mar', 'Apr'], 400);
    expect(p.layout, XLabelLayout.horizontal);
    expect(p.step, 1);
    expect(p.reserved, 28);
  });

  test('labels with spaces wrap to two lines before they are turned', () {
    // 4 labels of 20 chars = 120 px in a 100 px slot; words are 6-10 chars.
    final p = plan([
      'Wireless Mouse Pro',
      'Standing Desk Mat',
      'Studio Headphones',
      'Multiport Dock USB',
    ], 400);
    expect(p.layout, XLabelLayout.wrapped);
    expect(p.step, 1);
    expect(p.reserved, 13 * 2 + 15);
  });

  test('a long word cannot wrap, so the labels are turned and all kept', () {
    final p = plan(['a' * 30, 'b' * 30], 150);
    expect(p.layout, XLabelLayout.rotated);
    expect(p.step, 1);
    expect(p.labelMaxWidth, ChartAxisLabels.maxRotatedWidth);
  });

  test('turned labels are cut at the maximum width', () {
    final p = plan(['x' * 100, 'y' * 100], 120);
    expect(p.layout, XLabelLayout.rotated);
    expect(p.labelMaxWidth, ChartAxisLabels.maxRotatedWidth);
    // (110 + 13) * sin(45 deg) + 10
    expect(p.reserved, closeTo(97.0, 0.1));
  });

  test('many points thin the turned labels out, as the last resort', () {
    final labels = [for (var i = 0; i < 200; i++) 'category-$i'];
    final p = plan(labels, 700);
    expect(p.layout, XLabelLayout.rotated);
    expect(p.step, greaterThan(1));
    // Two drawn labels are at least 1.5 lines apart.
    expect(p.slot, greaterThanOrEqualTo(13 * 1.5));
  });

  test('no labels give a plan without dividing by zero', () {
    final p = plan(const [], 300);
    expect(p.step, 1);
    expect(p.slot, 300);
  });

  test('ellipsize keeps short text and cuts long text with one character', () {
    expect(ChartAxisLabels.ellipsize('short', 10), 'short');
    expect(ChartAxisLabels.ellipsize('a very long label', 8), 'a very…');
    expect(ChartAxisLabels.ellipsize('abc', 1), 'abc');
  });
}
