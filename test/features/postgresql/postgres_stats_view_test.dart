import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_stats_view.dart';
import 'package:querya_desktop/shared/widgets/querya_sparkline.dart';

import '../../support/querya_theme_test_shell.dart';

/// A server whose counters move on every poll. Counts each stats read.
class _CountingServer {
  int reads = 0;

  Future<Map<String, dynamic>> stats() async {
    reads++;
    return <String, dynamic>{
      'version': 'PostgreSQL 16.4 on x86_64-pc-linux-gnu',
      'connections_total': 10,
      'connections_active': 1 + reads,
      'connections_idle': 9 - reads,
      'settings': <String, String>{'max_connections': '100'},
      'databases': <Map<String, dynamic>>[
        {
          'datname': 'app',
          'size': 1024,
          'numbackends': 2,
          'xact_commit': 50 * reads,
          'xact_rollback': 0,
        },
      ],
    };
  }
}

const _row = ConnectionRow(
  id: 7,
  type: 'postgresql',
  name: 'pg',
  host: 'localhost',
  createdAt: '2026-01-01T00:00:00Z',
);

const _poll = Duration(seconds: 5);

void main() {
  Future<void> pumpView(WidgetTester t, material.Widget child) async {
    await t.binding.setSurfaceSize(const material.Size(1400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(child: child));
    await t.pump();
    await t.pump();
  }

  /// Samples per sparkline: connections first, transactions per second next.
  List<int> sampleCounts(WidgetTester t) => [
        for (final s
            in t.widgetList<QueryaSparkline>(find.byType(QueryaSparkline)))
          s.samples.length,
      ];

  group('PostgreSQL stats polling (#1165)', () {
    testWidgets('each poll reads the stats once and nothing more', (t) async {
      final server = _CountingServer();
      await pumpView(
          t, PostgresStatsView(connectionRow: _row, statsSource: server.stats));
      expect(server.reads, 1);

      await t.pump(_poll);
      expect(server.reads, 2);
      await t.pump(_poll);
      expect(server.reads, 3);

      // Disposing the view stops its timer.
      await t.pumpWidget(const material.SizedBox());
    });

    testWidgets('sparklines start after the second poll and grow with each',
        (t) async {
      final server = _CountingServer();
      await pumpView(
          t, PostgresStatsView(connectionRow: _row, statsSource: server.stats));
      // A rate needs two polls: one connection sample, no transaction rate.
      expect(sampleCounts(t), [1, 0]);

      await t.pump(_poll);
      expect(sampleCounts(t), [2, 1]);
      await t.pump(_poll);
      expect(sampleCounts(t), [3, 2]);

      await t.pumpWidget(const material.SizedBox());
    });

    testWidgets('a hidden Overview stops polling and keeps its history',
        (t) async {
      final server = _CountingServer();
      final visible = material.ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      await pumpView(
        t,
        material.ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, on, child) =>
              material.TickerMode(enabled: on, child: child!),
          child: PostgresStatsView(
              connectionRow: _row, statsSource: server.stats),
        ),
      );
      await t.pump(_poll);
      expect(server.reads, 2);

      visible.value = false;
      await t.pump();
      await t.pump(_poll * 3);
      expect(server.reads, 2, reason: 'no poll while hidden');

      visible.value = true;
      await t.pump();
      await t.pump(_poll);
      expect(server.reads, 3);
      // The samples taken before the pause are still there.
      expect(sampleCounts(t).first, 3);

      await t.pumpWidget(const material.SizedBox());
    });
  });
}
