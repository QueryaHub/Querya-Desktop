import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/stats/metric_history.dart';

void main() {
  group('MetricHistory (#1165)', () {
    test('keeps only the newest samples up to the capacity', () {
      final h = MetricHistory(capacity: 3);
      final t = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 5; i++) {
        h.record('active', i.toDouble(), t.add(Duration(seconds: i)));
      }
      expect(h.series('active').map((s) => s.value), [2, 3, 4]);
    });

    test('a counter gives a rate per second from its change', () {
      final h = MetricHistory();
      final t = DateTime.utc(2026, 1, 1);
      h.recordCounter('tps', 1000, t);
      expect(h.series('tps'), isEmpty, reason: 'the first sample has no rate');
      h.recordCounter('tps', 1100, t.add(const Duration(seconds: 5)));
      expect(h.series('tps').single.value, 20);
    });

    test('a counter that went down (a restart) gives no rate', () {
      final h = MetricHistory();
      final t = DateTime.utc(2026, 1, 1);
      h.recordCounter('tps', 1000, t);
      h.recordCounter('tps', 10, t.add(const Duration(seconds: 5)));
      expect(h.series('tps'), isEmpty);
      h.recordCounter('tps', 60, t.add(const Duration(seconds: 10)));
      expect(h.series('tps').single.value, 10);
    });

    test('series are read-only and unknown metrics are empty', () {
      final h = MetricHistory();
      expect(h.series('nothing'), isEmpty);
      h.record('a', 1, DateTime.utc(2026));
      expect(() => h.series('a').add(MetricSample(DateTime.utc(2026), 2)),
          throwsUnsupportedError);
    });
  });
}
