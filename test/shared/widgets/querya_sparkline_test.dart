import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/stats/metric_history.dart';
import 'package:querya_desktop/shared/widgets/querya_sparkline.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  Future<void> pumpSparkline(
    WidgetTester t,
    List<MetricSample> samples,
  ) async {
    await t.pumpWidget(queryaThemeTestShell(
      child: QueryaSparkline(
        samples: samples,
        color: material.Colors.blue,
      ),
    ));
    await t.pump();
  }

  String tooltipMessage(WidgetTester t) =>
      t.widget<material.Tooltip>(find.byType(material.Tooltip)).message!;

  group('QueryaSparkline (#1165)', () {
    testWidgets('no tooltip before the first sample', (t) async {
      await pumpSparkline(t, const []);
      expect(find.byType(material.Tooltip), findsNothing);
    });

    testWidgets('one sample: the tooltip names it, with its time', (t) async {
      await pumpSparkline(t, [
        MetricSample(DateTime(2026, 10, 9, 12, 0, 6), 42.5),
      ]);
      expect(tooltipMessage(t), '42.5 at 12:00:06');
    });

    testWidgets('the tooltip names the newest sample when more arrive',
        (t) async {
      await pumpSparkline(t, [
        MetricSample(DateTime(2026, 10, 9, 12, 0, 1), 10),
        MetricSample(DateTime(2026, 10, 9, 12, 0, 6), 42.5),
      ]);
      expect(tooltipMessage(t), '42.5 at 12:00:06');

      await pumpSparkline(t, [
        MetricSample(DateTime(2026, 10, 9, 12, 0, 1), 10),
        MetricSample(DateTime(2026, 10, 9, 12, 0, 6), 42.5),
        MetricSample(DateTime(2026, 10, 9, 12, 0, 11), 7.3),
      ]);
      expect(tooltipMessage(t), '7.3 at 12:00:11');
    });

    testWidgets('values from 100 show as whole numbers', (t) async {
      await pumpSparkline(t, [
        MetricSample(DateTime(2026, 10, 9, 12, 0, 1), 1234.6),
      ]);
      expect(tooltipMessage(t), '1235 at 12:00:01');
    });

    testWidgets('a flat series does not throw', (t) async {
      await pumpSparkline(t, [
        MetricSample(DateTime(2026, 10, 9, 12, 0, 1), 5),
        MetricSample(DateTime(2026, 10, 9, 12, 0, 6), 5),
      ]);
      expect(t.takeException(), isNull);
    });
  });
}
