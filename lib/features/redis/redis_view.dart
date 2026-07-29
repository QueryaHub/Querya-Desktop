import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 3);
const _summaryChipHeight = 88.0;
const _gridCardMinHeight = 220.0;

const _redisFieldLabels = <String, String>{
  'redis_version': 'Version',
  'redis_mode': 'Mode',
  'os': 'OS',
  'tcp_port': 'Port',
  'uptime_in_days': 'Uptime (days)',
  'config_file': 'Config file',
  'connected_clients': 'Connected',
  'blocked_clients': 'Blocked',
  'maxclients': 'Max clients',
  'client_recent_max_input_buffer': 'Max input buffer',
  'client_recent_max_output_buffer': 'Max output buffer',
  'rdb_bgsave_in_progress': 'BGSAVE in progress',
  'rdb_last_save_time': 'Last RDB save',
  'rdb_last_bgsave_status': 'Last BGSAVE status',
  'aof_enabled': 'AOF enabled',
  'aof_last_rewrite_time_sec': 'Last AOF rewrite',
  'role': 'Role',
  'connected_slaves': 'Connected replicas',
  'master_repl_offset': 'Repl offset',
};

class RedisView extends material.StatefulWidget {
  const RedisView({
    super.key,
    required this.connectionRow,
    this.connection,
    this.onBack,
  });

  final ConnectionRow connectionRow;

  /// An already-open [RedisConnection]. When provided the view re-uses it
  /// instead of creating (and potentially killing) a shared one.
  final RedisConnection? connection;

  /// Called when the user taps the "back to explorer" button.
  final material.VoidCallback? onBack;

  @override
  material.State<RedisView> createState() => _RedisViewState();
}

class _RedisViewState extends material.State<RedisView> {
  RedisConnection? _connection;
  RedisInfoSections? _info;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RedisView oldWidget) {
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

  /// Whether this view owns its connection (created it itself).
  bool _ownsConnection = false;

  /// Safely disconnects and clears the current Redis connection.
  void _disconnectCurrent() {
    final conn = _connection;
    _connection = null;
    if (conn != null && _ownsConnection) {
      conn.disconnect();
    }
    _ownsConnection = false;
  }

  Future<void> _load() async {
    _timer?.cancel();
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final supplied = widget.connection;
      RedisConnection conn;
      if (supplied != null && supplied.isConnected) {
        conn = supplied;
        _ownsConnection = false;
      } else {
        conn = RedisService.instance.createConnection(widget.connectionRow);
        await conn.connect();
        _ownsConnection = true;
      }
      if (!mounted) {
        if (_ownsConnection) conn.disconnect();
        return;
      }
      _connection = conn;
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

  Future<void> _fetch() async {
    final c = _connection;
    if (c == null) return;
    final raw = await c.info();
    final info = parseRedisInfo(raw);
    if (!mounted) return;
    final changed = replaceIfChanged(_info, info, (v) => _info = v);
    if (!changed && !_loading) return;
    setState(() => _loading = false);
  }

  Future<void> _onPollTick() async {
    final c = _connection;
    if (c == null || !c.isConnected) return;
    try {
      final raw = await c.info();
      final info = parseRedisInfo(raw);
      if (!mounted) return;
      if (!replaceIfChanged(_info, info, (v) => _info = v)) return;
      setState(() => _info = info);
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
              material.Icon(material.Icons.error_outline_rounded,
                  size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(err,
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

    final info = _info;
    if (info == null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(material.Icons.error_outline_rounded,
                  size: 48, color: cs.destructive),
              const Gap(16),
              const Text('No stats available').large().semiBold(),
              const Gap(8),
              const Text('Redis INFO returned no data.').muted().small(),
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
                _summaryChips(context, info),
                const Gap(24),
                _gridRow(
                  _memoryCard(context, info),
                  _statsCard(context, info),
                ),
                const Gap(16),
                _gridRow(
                  _cpuCard(context, info),
                  _keyspaceCard(context, info),
                ),
                const Gap(24),
                _sectionCard(context, 'Server', info['Server'], keys: const [
                  'redis_version',
                  'redis_mode',
                  'os',
                  'tcp_port',
                  'uptime_in_days',
                  'config_file',
                ]),
                const Gap(12),
                material.LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (!wide) {
                      return material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.stretch,
                        children: [
                          _sectionCard(context, 'Clients', info['Clients']),
                          const Gap(12),
                          _sectionCard(
                              context, 'Persistence', info['Persistence'],
                              keys: const [
                                'rdb_bgsave_in_progress',
                                'rdb_last_save_time',
                                'rdb_last_bgsave_status',
                                'aof_enabled',
                                'aof_last_rewrite_time_sec',
                              ]),
                        ],
                      );
                    }
                    return material.Row(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        material.Expanded(
                          child:
                              _sectionCard(context, 'Clients', info['Clients']),
                        ),
                        const Gap(16),
                        material.Expanded(
                          child: _sectionCard(
                              context, 'Persistence', info['Persistence'],
                              keys: const [
                                'rdb_bgsave_in_progress',
                                'rdb_last_save_time',
                                'rdb_last_bgsave_status',
                                'aof_enabled',
                                'aof_last_rewrite_time_sec',
                              ]),
                        ),
                      ],
                    );
                  },
                ),
                const Gap(12),
                _sectionCard(context, 'Replication', info['Replication']),
                const Gap(12),
                _errorStatsCard(context, info),
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
          child: material.Icon(material.Icons.memory_rounded,
              size: 28, color: cs.primary),
        ),
        const Gap(16),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(widget.connectionRow.name).large().semiBold(),
              const Gap(4),
              Text('${widget.connectionRow.host ?? 'localhost'}:${widget.connectionRow.port ?? 6379}')
                  .muted()
                  .small(),
            ],
          ),
        ),
        if (widget.onBack != null) ...[
          OutlineButton(
            onPressed: widget.onBack,
            leading:
                const material.Icon(material.Icons.grid_view_rounded, size: 18),
            child: const Text('Explorer'),
          ),
          const Gap(8),
        ],
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

  String _formatUptime(RedisInfoSections info) {
    final seconds = sectionInt(info, 'Server', 'uptime_in_seconds');
    if (seconds == null || seconds <= 0) return '0m';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String _labelFor(String key) =>
      _redisFieldLabels[key] ?? key.replaceAll('_', ' ');

  material.Widget _summaryChips(
      material.BuildContext context, RedisInfoSections info) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final version = sectionValue(info, 'Server', 'redis_version') ?? '—';
    final uptime = _formatUptime(info);
    final clients = sectionInt(info, 'Clients', 'connected_clients') ?? 0;
    final maxClients = sectionInt(info, 'Clients', 'maxclients') ?? 0;
    final ops = sectionInt(info, 'Stats', 'instantaneous_ops_per_sec') ?? 0;
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
        chip('Version', version, material.Icons.tag_rounded),
        const Gap(12),
        chip('Uptime', uptime, material.Icons.schedule_rounded),
        const Gap(12),
        chip('Clients', '$clients / $maxClients',
            material.Icons.people_outline_rounded),
        const Gap(12),
        chip('Ops/s', '$ops', material.Icons.speed_rounded),
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

  material.Widget _memoryCard(
      material.BuildContext context, RedisInfoSections info) {
    final usedHuman = sectionValue(info, 'Memory', 'used_memory_human') ?? '—';
    final peakHuman =
        sectionValue(info, 'Memory', 'used_memory_peak_human') ?? '—';
    final frag =
        sectionDouble(info, 'Memory', 'mem_fragmentation_ratio') ?? 0.0;
    final rss = sectionValue(info, 'Memory', 'used_memory_rss_human') ?? '—';
    return _card(
      context,
      'Memory',
      _metricList(
        context,
        [
          _metricRow(context, 'Used', usedHuman),
          _metricRow(context, 'Peak', peakHuman),
          _metricRow(context, 'RSS', rss),
          _metricRow(context, 'Fragmentation', '${frag.toStringAsFixed(2)}×'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _statsCard(
      material.BuildContext context, RedisInfoSections info) {
    final ops = sectionInt(info, 'Stats', 'instantaneous_ops_per_sec') ?? 0;
    final totalOps = sectionInt(info, 'Stats', 'total_commands_processed');
    final keyspaceHits = sectionInt(info, 'Stats', 'keyspace_hits') ?? 0;
    final keyspaceMisses = sectionInt(info, 'Stats', 'keyspace_misses') ?? 0;
    final total = keyspaceHits + keyspaceMisses;
    final hitRate =
        total > 0 ? (keyspaceHits / total * 100).toStringAsFixed(1) : '—';
    return _card(
      context,
      'Performance',
      _metricList(
        context,
        [
          _metricRow(context, 'Ops/s', '$ops'),
          _metricRow(context, 'Total commands', totalOps?.toString() ?? '—'),
          _metricRow(
              context, 'Hits / misses', '$keyspaceHits / $keyspaceMisses'),
          _metricRow(
              context, 'Hit rate', hitRate == '—' ? hitRate : '$hitRate%'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _keyspaceCard(
      material.BuildContext context, RedisInfoSections info) {
    final keyspace = info['Keyspace'];
    final rows = <material.Widget>[];
    if (keyspace != null && keyspace.isNotEmpty) {
      final entries = keyspace.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        rows.add(
            _metricRow(context, entry.key, _formatKeyspaceEntry(entry.value)));
      }
    } else {
      rows.add(
        material.Padding(
          padding: const material.EdgeInsets.symmetric(vertical: 8),
          child: const Text('No keys in any database').muted().small(),
        ),
      );
    }
    return _card(
      context,
      'Keyspace',
      _metricList(context, rows, stretch: true),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  String _formatKeyspaceEntry(String raw) {
    var keys = 0;
    var expires = 0;
    int? avgTtlMs;
    for (final part in raw.split(',')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final name = kv[0].trim();
      final value = kv[1].trim();
      switch (name) {
        case 'keys':
          keys = int.tryParse(value) ?? 0;
        case 'expires':
          expires = int.tryParse(value) ?? 0;
        case 'avg_ttl':
          avgTtlMs = int.tryParse(value);
      }
    }
    final ttlPart = (avgTtlMs != null && avgTtlMs > 0)
        ? ' · avg TTL ${_formatDurationMs(avgTtlMs)}'
        : '';
    return '$keys keys · $expires with TTL$ttlPart';
  }

  String _formatDurationMs(int ms) {
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${(seconds / 3600).toStringAsFixed(1)}h';
    return '${(seconds / 86400).toStringAsFixed(1)}d';
  }

  material.Widget _cpuCard(
      material.BuildContext context, RedisInfoSections info) {
    final sys = sectionDouble(info, 'CPU', 'used_cpu_sys_main_thread');
    final user = sectionDouble(info, 'CPU', 'used_cpu_user_main_thread');
    return _card(
      context,
      'CPU (main thread)',
      _metricList(
        context,
        [
          _metricRow(context, 'System', sys?.toStringAsFixed(2) ?? '—'),
          _metricRow(context, 'User', user?.toStringAsFixed(2) ?? '—'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _sectionCard(
      material.BuildContext context, String title, Map<String, String>? data,
      {List<String>? keys}) {
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    final entries = keys != null
        ? keys
            .map((k) => MapEntry(k, data[k]))
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value as String))
            .toList()
        : data.entries.toList();
    if (entries.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      title,
      _twoColumnMetrics(
        context,
        entries.map((e) => MapEntry(_labelFor(e.key), e.value)).toList(),
      ),
    );
  }

  material.Widget _twoColumnMetrics(
    material.BuildContext context,
    List<MapEntry<String, String>> entries,
  ) {
    if (entries.length <= 4) {
      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          for (final e in entries) _metricRow(context, e.key, e.value)
        ],
      );
    }
    final mid = (entries.length / 2).ceil();
    final left = entries.sublist(0, mid);
    final right = entries.sublist(mid);
    return material.Row(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              for (final e in left) _metricRow(context, e.key, e.value)
            ],
          ),
        ),
        const Gap(24),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              for (final e in right) _metricRow(context, e.key, e.value)
            ],
          ),
        ),
      ],
    );
  }

  material.Widget _errorStatsCard(
      material.BuildContext context, RedisInfoSections info) {
    final data = info['Errorstats'];
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      'Error stats',
      material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          for (final e in data.entries)
            _metricRow(context, _labelFor(e.key), e.value),
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
}
