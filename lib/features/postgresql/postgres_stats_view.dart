import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';
import 'package:querya_desktop/core/stats/metric_history.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/querya_sparkline.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 5);
const _summaryChipHeight = 88.0;
const _gridCardMinHeight = 220.0;
final _pgVersionPattern = RegExp(r'PostgreSQL\s+([\d.]+)');

class PostgresStatsView extends material.StatefulWidget {
  const PostgresStatsView({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<PostgresStatsView> createState() => _PostgresStatsViewState();
}

/// Adds one poll's numbers to [history]: connections as they are, and the
/// commits of all databases as a rate per second (a counter).
@visibleForTesting
void recordServerStats(
  MetricHistory history,
  Map<String, dynamic> stats,
  DateTime now,
) {
  history
    ..record('connections_active',
        ((stats['connections_active'] ?? 0) as num).toDouble(), now)
    ..record('connections_total',
        ((stats['connections_total'] ?? 0) as num).toDouble(), now);
  var commits = 0;
  for (final db in stats['databases'] as List? ?? const []) {
    commits += ((db as Map)['xact_commit'] as num? ?? 0).toInt();
  }
  history.recordCounter('transactions_per_second', commits.toDouble(), now);
}

class _PostgresStatsViewState extends material.State<PostgresStatsView> {
  PgLease? _lease;
  PostgresConnection? get _connection => _lease?.connection;

  Map<String, dynamic>? _stats;

  /// Samples of the last poll results: connections and transactions per second.
  final _history = MetricHistory();
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PostgresStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _timer?.cancel();
      _disconnectCurrent();
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disconnectCurrent();
    super.dispose();
  }

  /// Releases the lease. The session is shared with the object tree, other
  /// views and MCP, so closing this view never interrupts it.
  void _disconnectCurrent() {
    _lease?.release();
    _lease = null;
  }

  Future<void> _load() async {
    _timer?.cancel();
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _stats = null;
    });
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.connectionRow.databaseName ?? 'postgres',
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch();
      if (mounted) _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Records the poll's numbers. No query is added: the poll already fetched them.
  void _recordHistory(Map<String, dynamic> stats) =>
      recordServerStats(_history, stats, DateTime.now());

  Future<void> _fetch() async {
    final c = _connection;
    if (c == null || !c.isConnected) {
      if (!mounted) return;
      setState(() {
        _error = 'Not connected';
        _loading = false;
      });
      return;
    }
    try {
      final stats = await c.serverStats();
      if (!mounted) return;
      _recordHistory(stats);
      if (!replaceIfChanged(_stats, stats, (v) => _stats = v)) {
        if (_loading) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onPollTick() async {
    final c = _connection;
    if (c == null || !c.isConnected) return;
    try {
      final stats = await c.serverStats();
      if (!mounted) return;
      _recordHistory(stats);
      // The sparklines move with every sample, so rebuild even when the numbers
      // did not change.
      setState(() => replaceIfChanged(_stats, stats, (v) => _stats = v));
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_onPollTick()));
  }

  @override
  material.Widget build(material.BuildContext context) {
    final c = _connection;
    _timer = syncTickerGatedPeriodicTimer(
      context: context,
      timer: _timer,
      shouldRun: c != null && c.isConnected && !_loading,
      interval: _pollInterval,
      onTick: () => unawaited(_onPollTick()),
    );

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const material.Center(
        child: QueryaSpinner(
          size: QueryaSpinnerSize.lg,
          label: 'Connecting...',
        ),
      );
    }

    if (_error != null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(material.Icons.error_outline_rounded,
                  size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(_error!,
                  style: material.TextStyle(
                      color: cs.mutedForeground, fontSize: 13)),
              const Gap(24),
              OutlineButton(
                onPressed: _load,
                leading: const material.Icon(material.Icons.refresh_rounded,
                    size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats;
    if (stats == null) return material.Container(color: cs.background);

    return material.Container(
      color: cs.background,
      child: material.RefreshIndicator(
        onRefresh: _fetch,
        child: material.LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.max(0.0, constraints.maxWidth - 48);
            final isNarrow = contentWidth < 560;
            return material.SingleChildScrollView(
              physics: const material.AlwaysScrollableScrollPhysics(),
              padding: const material.EdgeInsets.all(24),
              child: material.SizedBox(
                width: contentWidth,
                child: material.Column(
                  mainAxisSize: material.MainAxisSize.min,
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const Gap(24),
                    _summaryChips(context, stats),
                    const Gap(24),
                    if (isNarrow)
                      material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.stretch,
                        children: [
                          _connectionsCard(context, stats),
                          const Gap(16),
                          _serverSettingsCard(context, stats),
                        ],
                      )
                    else
                      material.Row(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          material.Expanded(
                              child: _connectionsCard(context, stats)),
                          const Gap(16),
                          material.Expanded(
                              child: _serverSettingsCard(context, stats)),
                        ],
                      ),
                    const Gap(16),
                    _databasesCard(context, stats),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  material.Widget _header(material.BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.LayoutBuilder(
      builder: (context, constraints) {
        return material.SingleChildScrollView(
          scrollDirection: material.Axis.horizontal,
          child: material.ConstrainedBox(
            constraints:
                material.BoxConstraints(minWidth: constraints.maxWidth),
            child: material.Row(
              mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
              children: [
                material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Container(
                      padding: const material.EdgeInsets.all(10),
                      decoration: material.BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: material.BorderRadius.circular(12),
                      ),
                      child: material.SizedBox(
                        width: 28,
                        height: 28,
                        child: material.Image.asset(
                          'assets/images/postgresql_icon.png',
                          cacheWidth: (32 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          cacheHeight: (32 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                          fit: material.BoxFit.contain,
                          errorBuilder: (_, __, ___) => material.Icon(
                              material.Icons.storage_rounded,
                              size: 28,
                              color: cs.primary),
                        ),
                      ),
                    ),
                    const Gap(16),
                    material.ConstrainedBox(
                      constraints: const material.BoxConstraints(maxWidth: 420),
                      child: material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          Text(widget.connectionRow.name).large().semiBold(),
                          const Gap(4),
                          Text('${widget.connectionRow.host ?? 'localhost'}:${widget.connectionRow.port ?? 5432}')
                              .muted()
                              .small(),
                        ],
                      ),
                    ),
                  ],
                ),
                OutlineButton(
                  onPressed: _load,
                  leading: const material.Icon(material.Icons.refresh_rounded,
                      size: 18),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  material.Widget _summaryChips(
      material.BuildContext context, Map<String, dynamic> stats) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final versionFull = stats['version'] as String? ?? '—';
    final versionShort = _extractPgVersion(versionFull);
    final settings = stats['settings'] as Map<String, String>? ?? {};
    final maxConn = settings['max_connections'] ?? '—';
    final totalConn = stats['connections_total'] ?? 0;
    final uptimeSec = stats['uptime_seconds'] as int?;
    final uptimeStr = uptimeSec != null
        ? '${uptimeSec ~/ 86400}d ${(uptimeSec % 86400) ~/ 3600}h'
        : '—';
    final dbSize = stats['current_db_size'];
    final dbSizeStr = dbSize != null ? _formatBytes(dbSize as int) : '—';

    material.Widget chip(String label, String value, material.IconData icon) {
      return material.Expanded(
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(
            minHeight: _summaryChipHeight,
          ),
          child: material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: material.BoxDecoration(
              color: cs.card,
              borderRadius: material.BorderRadius.circular(10),
              border:
                  material.Border.all(color: cs.border.withValues(alpha: 0.5)),
            ),
            child: material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Padding(
                  padding: const material.EdgeInsets.only(top: 2),
                  child: material.Icon(icon, size: 20, color: cs.primary),
                ),
                const Gap(12),
                material.Expanded(
                  child: material.Column(
                    mainAxisAlignment: material.MainAxisAlignment.center,
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      Text(label).muted().xSmall(),
                      const Gap(2),
                      material.Text(
                        value,
                        maxLines: 2,
                        overflow: material.TextOverflow.ellipsis,
                        style: material.TextStyle(
                          fontSize: 13,
                          fontWeight: material.FontWeight.w600,
                          color: cs.foreground,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return material.Row(
      children: [
        chip('Version', versionShort, material.Icons.tag_rounded),
        const Gap(12),
        chip('Uptime', uptimeStr, material.Icons.schedule_rounded),
        const Gap(12),
        chip('Connections', '$totalConn / $maxConn',
            material.Icons.people_outline_rounded),
        const Gap(12),
        chip('DB Size', dbSizeStr, material.Icons.storage_rounded),
      ],
    );
  }

  material.Widget _card(
      material.BuildContext context, String title, material.Widget body,
      {double? minHeight}) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Container(
      width: double.infinity,
      constraints: minHeight != null
          ? material.BoxConstraints(minHeight: minHeight)
          : const material.BoxConstraints(),
      padding: const material.EdgeInsets.all(20),
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(12),
        border: material.Border.all(color: cs.border.withValues(alpha: 0.4)),
      ),
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          Text(title).semiBold(),
          const Gap(12),
          body,
        ],
      ),
    );
  }

  material.Widget _connectionsCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    final total = stats['connections_total'] ?? 0;
    final active = stats['connections_active'] ?? 0;
    final idle = stats['connections_idle'] ?? 0;
    final settings = stats['settings'] as Map<String, String>? ?? {};
    final maxConn = settings['max_connections'] ?? '—';
    return _card(
      context,
      'Connections',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Total', '$total'),
          _row(context, 'Active', '$active'),
          _row(context, 'Idle', '$idle'),
          _row(context, 'Max connections', maxConn),
          const Gap(8),
          QueryaSparkline(
            samples: _history.series('connections_active'),
            color: context.workbench.accent,
          ),
          QueryaSparkline(
            samples: _history.series('transactions_per_second'),
            color: context.workbench.accent,
          ),
        ],
      ),
      minHeight: _gridCardMinHeight,
    );
  }

  material.Widget _serverSettingsCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    final settings = stats['settings'] as Map<String, String>? ?? {};
    return _card(
      context,
      'Server Settings',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Shared buffers', settings['shared_buffers'] ?? '—'),
          _row(context, 'Work mem', settings['work_mem'] ?? '—'),
          _row(context, 'Effective cache',
              settings['effective_cache_size'] ?? '—'),
          _row(context, 'Encoding', settings['server_encoding'] ?? '—'),
          _row(context, 'Timezone', settings['timezone'] ?? '—'),
        ],
      ),
      minHeight: _gridCardMinHeight,
    );
  }

  material.Widget _databasesCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    final databases = stats['databases'] as List<Map<String, dynamic>>? ?? [];
    if (databases.isEmpty) return const material.SizedBox.shrink();

    final cs = shadcn.Theme.of(context).colorScheme;
    return _card(
      context,
      'Databases',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Header
          material.Padding(
            padding: const material.EdgeInsets.only(bottom: 8),
            child: material.Row(
              children: [
                material.SizedBox(
                    width: 140, child: const Text('Name').muted().xSmall()),
                material.SizedBox(
                    width: 80, child: const Text('Size').muted().xSmall()),
                material.SizedBox(
                    width: 70, child: const Text('Backends').muted().xSmall()),
                material.SizedBox(
                    width: 80, child: const Text('Commits').muted().xSmall()),
                material.SizedBox(
                    width: 80, child: const Text('Rollbacks').muted().xSmall()),
                material.Expanded(
                    child: const Text('Hit ratio').muted().xSmall()),
              ],
            ),
          ),
          material.Divider(height: 1, color: cs.border.withValues(alpha: 0.3)),
          for (final db in databases)
            material.Padding(
              padding: const material.EdgeInsets.symmetric(vertical: 5),
              child: material.Row(
                children: [
                  material.SizedBox(
                    width: 140,
                    child: material.Text(
                      '${db['datname']}',
                      style: material.TextStyle(
                          fontSize: 13, color: cs.foreground),
                      overflow: material.TextOverflow.ellipsis,
                    ),
                  ),
                  material.SizedBox(
                    width: 80,
                    child: Text(_formatBytes((db['size'] as int?) ?? 0))
                        .muted()
                        .xSmall(),
                  ),
                  material.SizedBox(
                    width: 70,
                    child: Text('${db['numbackends'] ?? 0}').muted().xSmall(),
                  ),
                  material.SizedBox(
                    width: 80,
                    child: Text('${db['xact_commit'] ?? 0}').muted().xSmall(),
                  ),
                  material.SizedBox(
                    width: 80,
                    child: Text('${db['xact_rollback'] ?? 0}').muted().xSmall(),
                  ),
                  material.Expanded(
                    child: Text(_hitRatio(db)).muted().xSmall(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  material.Widget _row(
      material.BuildContext context, String key, String value) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(vertical: 4),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.SizedBox(width: 160, child: Text(key).muted().small()),
          material.Expanded(
              child: material.SelectableText(value,
                  style:
                      material.TextStyle(fontSize: 13, color: cs.foreground))),
        ],
      ),
    );
  }

  String _extractPgVersion(String full) {
    final match = _pgVersionPattern.firstMatch(full);
    return match?.group(1) ?? full;
  }

  String _hitRatio(Map<String, dynamic> db) {
    final hits = (db['blks_hit'] as int?) ?? 0;
    final reads = (db['blks_read'] as int?) ?? 0;
    final total = hits + reads;
    if (total == 0) return '—';
    return '${(hits / total * 100).toStringAsFixed(1)}%';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
