import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/stats/metric_history.dart';
import 'package:querya_desktop/features/postgresql/postgres_stats_view.dart';

Map<String, dynamic> _stats({
  int active = 3,
  int total = 10,
  List<int> commits = const [5],
}) =>
    {
      'connections_active': active,
      'connections_total': total,
      'databases': [
        for (final c in commits) {'xact_commit': c},
      ],
    };

void main() {
  final t0 = DateTime.utc(2026, 10, 9, 12);

  group('server stats history (#1165)', () {
    test('the first poll records the connections, no transaction rate', () {
      final h = MetricHistory();
      recordServerStats(h, _stats(), t0);
      expect(h.series('connections_active').map((s) => s.value), [3]);
      expect(h.series('connections_total').map((s) => s.value), [10]);
      expect(h.series('transactions_per_second'), isEmpty);
    });

    test('the second poll gives the first transaction rate', () {
      final h = MetricHistory();
      recordServerStats(h, _stats(commits: [100]), t0);
      recordServerStats(
        h,
        _stats(commits: [130, 20]),
        t0.add(const Duration(seconds: 5)),
      );
      // 150 commits in all, 100 before: 50 in five seconds.
      expect(h.series('transactions_per_second').single.value, 10);
      expect(h.series('connections_active'), hasLength(2));
    });

    test('a database that reports no commits counts as zero', () {
      final h = MetricHistory();
      recordServerStats(h, {'databases': [{}]}, t0);
      recordServerStats(
        h,
        {'databases': [{}]},
        t0.add(const Duration(seconds: 5)),
      );
      expect(h.series('transactions_per_second').single.value, 0);
    });

    test('a server restart (counters go down) gives no negative rate', () {
      final h = MetricHistory();
      recordServerStats(h, _stats(commits: [500]), t0);
      recordServerStats(
        h,
        _stats(commits: [4]),
        t0.add(const Duration(seconds: 5)),
      );
      expect(h.series('transactions_per_second'), isEmpty);
    });

    test('a poll without databases still records the connections', () {
      final h = MetricHistory();
      recordServerStats(
        h,
        {'connections_active': 1, 'connections_total': 2},
        t0,
      );
      expect(h.series('connections_active').single.value, 1);
      expect(h.series('connections_total').single.value, 2);
      expect(h.series('transactions_per_second'), isEmpty);
    });

    test('a poll with missing connection counts records zero', () {
      final h = MetricHistory();
      recordServerStats(h, const {}, t0);
      expect(h.series('connections_active').single.value, 0);
      expect(h.series('connections_total').single.value, 0);
    });
  });
}
