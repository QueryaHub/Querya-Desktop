import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 5);
const _summaryChipHeight = 88.0;
const _gridCardMinHeight = 220.0;
final _mysqlVersionPattern = RegExp(r'(\d+\.\d+(?:\.\d+)?)');

/// Server dashboard when a MySQL connection is selected without a tree object.
class MysqlStatsView extends material.StatefulWidget {
  const MysqlStatsView({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<MysqlStatsView> createState() => _MysqlStatsViewState();
}

class _MysqlStatsViewState extends material.State<MysqlStatsView> {
  MysqlLease? _lease;
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MysqlStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _timer?.cancel();
      _disconnect();
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disconnect();
    super.dispose();
  }

  void _disconnect() {
    _lease?.release();
    _lease = null;
  }

  Future<void> _load() async {
    _timer?.cancel();
    _disconnect();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _stats = null;
    });
    try {
      final lease = await MysqlService.instance.acquire(
        widget.connectionRow,
        database: widget.connectionRow.databaseName ?? '',
        mode: MysqlSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch();
      if (mounted) _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetch() async {
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) {
      if (!mounted) return;
      setState(() {
        _error = 'Not connected';
        _loading = false;
      });
      return;
    }
    try {
      final stats = await conn.serverStats();
      if (!mounted) return;
      if (!replaceIfChanged(_stats, stats, (v) => _stats = v)) {
        if (_loading) setState(() => _loading = false);
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onPollTick() async {
    final conn = _lease?.connection;
    if (conn == null || !conn.isConnected) return;
    try {
      final stats = await conn.serverStats();
      if (!mounted) return;
      if (!replaceIfChanged(_stats, stats, (v) => _stats = v)) return;
      setState(() => _stats = stats);
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_onPollTick()));
  }

  @override
  material.Widget build(material.BuildContext context) {
    final conn = _lease?.connection;
    _timer = syncTickerGatedPeriodicTimer(
      context: context,
      timer: _timer,
      shouldRun: conn != null && conn.isConnected && !_loading,
      interval: _pollInterval,
      onTick: () => unawaited(_onPollTick()),
    );

    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    if (_loading) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 32,
              height: 32,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(16),
            const Text('Connecting...').muted().small(),
          ],
        ),
      );
    }

    final err = _error;
    if (err != null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(
                material.Icons.error_outline_rounded,
                size: 48,
                color: cs.destructive,
              ),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(
                err,
                style:
                    material.TextStyle(color: cs.mutedForeground, fontSize: 13),
              ),
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
        child: material.SingleChildScrollView(
          physics: const material.AlwaysScrollableScrollPhysics(),
          padding: const material.EdgeInsets.all(24),
          child: material.SizedBox(
            width: width,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const Gap(24),
                _summaryChips(context, stats),
                const Gap(24),
                _gridRow(
                  _connectionsCard(context, stats),
                  _queriesCard(context, stats),
                ),
                const Gap(16),
                _gridRow(
                  _networkCard(context, stats),
                  _settingsCard(context, stats),
                ),
                const Gap(24),
                _databasesCard(context, stats),
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _header(material.BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Row(
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
              'assets/images/mysql_icon.png',
              cacheWidth: (28 * MediaQuery.devicePixelRatioOf(context)).toInt(),
              cacheHeight: (28 * MediaQuery.devicePixelRatioOf(context)).toInt(),
              fit: material.BoxFit.contain,
              errorBuilder: (_, __, ___) => material.Icon(
                material.Icons.storage_rounded,
                size: 28,
                color: cs.primary,
              ),
            ),
          ),
        ),
        const Gap(16),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(widget.connectionRow.name).large().semiBold(),
              const Gap(4),
              Text(
                '${widget.connectionRow.host ?? 'localhost'}:${widget.connectionRow.port ?? 3306}',
              ).muted().small(),
            ],
          ),
        ),
        OutlineButton(
          onPressed: _load,
          leading:
              const material.Icon(material.Icons.refresh_rounded, size: 18),
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  material.Widget _gridRow(material.Widget left, material.Widget right) {
    return material.IntrinsicHeight(
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Expanded(child: left),
          const Gap(16),
          material.Expanded(child: right),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '0m';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String _status(Map<String, dynamic> stats, String key) =>
      (stats['status'] as Map<String, String>?)?[key] ?? '—';

  String _variable(Map<String, dynamic> stats, String key) =>
      (stats['variables'] as Map<String, String>?)?[key] ?? '—';

  material.Widget _summaryChips(
      material.BuildContext context, Map<String, dynamic> stats) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final versionFull = stats['version'] as String? ?? '—';
    final versionShort = _extractMysqlVersion(versionFull);
    final uptimeSec = stats['uptime_seconds'] as int? ?? 0;
    final connected = _status(stats, 'Threads_connected');
    final maxConn = _variable(stats, 'max_connections');
    final questions = _status(stats, 'Questions');

    material.Widget chip(String label, String value, material.IconData icon) {
      return material.Expanded(
        child: material.ConstrainedBox(
          constraints:
              const material.BoxConstraints(minHeight: _summaryChipHeight),
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
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        chip('Version', versionShort, material.Icons.tag_rounded),
        const Gap(12),
        chip('Uptime', _formatUptime(uptimeSec),
            material.Icons.schedule_rounded),
        const Gap(12),
        chip('Connections', '$connected / $maxConn',
            material.Icons.people_outline_rounded),
        const Gap(12),
        chip('Queries', questions, material.Icons.speed_rounded),
      ],
    );
  }

  material.Widget _card(
    material.BuildContext context,
    String title,
    material.Widget body, {
    double? minHeight,
    bool stretchBody = false,
  }) {
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
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          Text(title).semiBold(),
          const Gap(12),
          if (stretchBody) material.Expanded(child: body) else body,
        ],
      ),
    );
  }

  material.Widget _metricList(
    material.BuildContext context,
    List<material.Widget> rows, {
    bool stretch = false,
  }) {
    final column = material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: rows,
    );
    if (!stretch) return column;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        column,
        const material.Spacer(),
      ],
    );
  }

  material.Widget _connectionsCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    return _card(
      context,
      'Connections',
      _metricList(
        context,
        [
          _metricRow(context, 'Connected', _status(stats, 'Threads_connected')),
          _metricRow(context, 'Running', _status(stats, 'Threads_running')),
          _metricRow(
              context, 'Max used', _status(stats, 'Max_used_connections')),
          _metricRow(
              context, 'Max allowed', _variable(stats, 'max_connections')),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _queriesCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    return _card(
      context,
      'Queries',
      _metricList(
        context,
        [
          _metricRow(context, 'Questions', _status(stats, 'Questions')),
          _metricRow(context, 'Slow queries', _status(stats, 'Slow_queries')),
          _metricRow(context, 'Open tables', _status(stats, 'Open_tables')),
          _metricRow(
              context, 'Aborted connects', _status(stats, 'Aborted_connects')),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _networkCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    final bytesIn = int.tryParse(_status(stats, 'Bytes_received')) ?? 0;
    final bytesOut = int.tryParse(_status(stats, 'Bytes_sent')) ?? 0;
    return _card(
      context,
      'Network',
      _metricList(
        context,
        [
          _metricRow(context, 'Bytes in', _formatBytes(bytesIn)),
          _metricRow(context, 'Bytes out', _formatBytes(bytesOut)),
          _metricRow(context, 'Total connects', _status(stats, 'Connections')),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _settingsCard(
      material.BuildContext context, Map<String, dynamic> stats) {
    final pool = int.tryParse(_variable(stats, 'innodb_buffer_pool_size')) ?? 0;
    return _card(
      context,
      'Server',
      _metricList(
        context,
        [
          _metricRow(context, 'InnoDB buffer pool', _formatBytes(pool)),
          _metricRow(
              context, 'Charset', _variable(stats, 'character_set_server')),
          _metricRow(
              context, 'Collation', _variable(stats, 'collation_server')),
          _metricRow(context, 'Port', _variable(stats, 'port')),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
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
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.only(bottom: 8),
            child: material.Row(
              children: [
                material.SizedBox(
                  width: 180,
                  child: const Text('Name').muted().xSmall(),
                ),
                material.SizedBox(
                  width: 100,
                  child: const Text('Size').muted().xSmall(),
                ),
                material.Expanded(
                  child: const Text('Tables').muted().xSmall(),
                ),
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
                    width: 180,
                    child: material.Text(
                      '${db['name']}',
                      style: material.TextStyle(
                          fontSize: 13, color: cs.foreground),
                      overflow: material.TextOverflow.ellipsis,
                    ),
                  ),
                  material.SizedBox(
                    width: 100,
                    child: Text(_formatBytes((db['size'] as int?) ?? 0))
                        .muted()
                        .xSmall(),
                  ),
                  material.Expanded(
                    child: Text('${db['tables'] ?? 0}').muted().xSmall(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  material.Widget _metricRow(
      material.BuildContext context, String label, String value) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(vertical: 6),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 2,
              overflow: material.TextOverflow.ellipsis,
            ).muted().small(),
          ),
          const Gap(12),
          material.Flexible(
            flex: 2,
            child: material.SelectableText(
              value,
              textAlign: material.TextAlign.right,
              maxLines: 2,
              style: material.TextStyle(
                fontSize: 13,
                fontWeight: material.FontWeight.w600,
                color: cs.foreground,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _extractMysqlVersion(String full) {
    final match = _mysqlVersionPattern.firstMatch(full);
    return match?.group(1) ?? full;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
