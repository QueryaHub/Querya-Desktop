import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_format.dart';

void main() {
  group('ChartFormat.full', () {
    test('groups thousands and drops .0 on integers', () {
      expect(ChartFormat.full(1234567), '1,234,567');
      expect(ChartFormat.full(42), '42');
      expect(ChartFormat.full(42.0), '42');
    });

    test('keeps up to two decimals without trailing zeros', () {
      expect(ChartFormat.full(1234.5), '1,234.5');
      expect(ChartFormat.full(0.1), '0.1');
      expect(ChartFormat.full(3.14159), '3.14');
      expect(ChartFormat.full(100.001), '100');
    });

    test('keeps the sign', () {
      expect(ChartFormat.full(-1234567), '-1,234,567');
      expect(ChartFormat.full(-42.5), '-42.5');
    });
  });

  group('ChartFormat.compact', () {
    test('uses M, k and B suffixes on axes', () {
      expect(ChartFormat.compact(1234567), '1.2M');
      expect(ChartFormat.compact(3400), '3.4k');
      expect(ChartFormat.compact(2000000000), '2B');
    });

    test('small values stay in full', () {
      expect(ChartFormat.compact(12), '12');
      expect(ChartFormat.compact(0.5), '0.5');
    });
  });
}
