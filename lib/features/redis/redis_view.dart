import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 3);
const _summaryChipHeight = 72.0;
const _gridCardHeight = 220.0;

class RedisView extends material.StatefulWidget {
  const RedisView({super.key, required this.connectionRow});
  final ConnectionRow connectionRow;

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

  /// Safely disconnects and clears the current Redis connection.
  void _disconnectCurrent() {
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      conn.disconnect(); // fire-and-forget; disconnect handles errors
    }
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
      final conn = RedisService.instance.createConnection(widget.connectionRow);
      await conn.connect();
      if (!mounted) {
        // Widget was disposed while connecting — clean up immediately.
        conn.disconnect();
        return;
      }
      _connection = conn;
      await _fetch();
      if (mounted) _startTimer();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetch() async {
    final c = _connection;
    if (c == null) return;
    final raw = await c.info();
    final info = parseRedisInfo(raw);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) async {
      final c = _connection;
      if (c == null || !c.isConnected) return;
      try {
        final raw = await c.info();
        final info = parseRedisInfo(raw);
        if (!mounted) return;
        setState(() => _info = info);
      } catch (_) {}
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    if (_loading) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.SizedBox(
              width: 32,
              height: 32,
              child: material.CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const Gap(16),
            Text('Connecting...').muted().small(),
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
              material.Icon(material.Icons.error_outline_rounded, size: 48, color: cs.destructive),
              const Gap(16),
              Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(err, style: material.TextStyle(color: cs.mutedForeground, fontSize: 13)),
              const Gap(24),
              OutlineButton(
                onPressed: _load,
                leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final info = _info;
    if (info == null) return material.Container(color: cs.background);

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
                material.Row(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    material.Expanded(child: _memoryCard(context, info)),
                    const Gap(16),
                    material.Expanded(child: _statsCard(context, info)),
                  ],
                ),
                const Gap(16),
                material.Row(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    material.Expanded(child: _keyspaceCard(context, info)),
                    const Gap(16),
                    material.Expanded(child: _cpuCard(context, info)),
                  ],
                ),
                const Gap(24),
                _sectionCard(context, 'Server', info['Server'], keys: const [
                  'redis_version', 'redis_mode', 'os', 'tcp_port', 'uptime_in_days', 'config_file',
                ]),
                const Gap(12),
                _sectionCard(context, 'Clients', info['Clients']),
                const Gap(12),
                _sectionCard(context, 'Persistence', info['Persistence'], keys: const [
                  'rdb_bgsave_in_progress', 'rdb_last_save_time', 'rdb_last_bgsave_status',
                  'aof_enabled', 'aof_last_rewrite_time_sec',
                ]),
                const Gap(12),
                _sectionCard(context, 'Replication', info['Replication']),
                const Gap(12),
                _errorStatsCard(context, info),
                const Gap(12),
                _sectionCard(context, 'Keyspace', info['Keyspace']),
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
          child: material.Icon(material.Icons.memory_rounded, size: 28, color: cs.primary),
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
                  .muted().small(),
            ],
          ),
        ),
        OutlineButton(
          onPressed: _load,
          leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  material.Widget _summaryChips(material.BuildContext context, RedisInfoSections info) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final version = sectionValue(info, 'Server', 'redis_version') ?? '—';
    final uptime = sectionInt(info, 'Server', 'uptime_in_days') ?? 0;
    final clients = sectionInt(info, 'Clients', 'connected_clients') ?? 0;
    final maxClients = sectionInt(info, 'Clients', 'maxclients') ?? 0;
    final ops = sectionInt(info, 'Stats', 'instantaneous_ops_per_sec') ?? 0;
    material.Widget chip(String label, String value, material.IconData icon) {
      return material.Expanded(
        child: material.SizedBox(
          height: _summaryChipHeight,
          child: material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: material.BoxDecoration(
              color: cs.card,
              borderRadius: material.BorderRadius.circular(10),
              border: material.Border.all(color: cs.border.withValues(alpha: 0.5)),
            ),
            child: material.Row(
              children: [
                material.Icon(icon, size: 20, color: cs.primary),
                const Gap(12),
                material.Expanded(
                  child: material.Column(
                    mainAxisAlignment: material.MainAxisAlignment.center,
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      Text(label).muted().xSmall(),
                      const Gap(2),
                      Text(value).semiBold().small(),
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
        chip('Version', version, material.Icons.tag_rounded),
        const Gap(12),
        chip('Uptime', '$uptime days', material.Icons.schedule_rounded),
        const Gap(12),
        chip('Clients', '$clients / $maxClients', material.Icons.people_outline_rounded),
        const Gap(12),
        chip('Ops/s', '$ops', material.Icons.speed_rounded),
      ],
    );
  }

  material.Widget _card(material.BuildContext context, String title, material.Widget body, {double? height}) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Container(
      width: double.infinity,
      height: height,
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

  material.Widget _memoryCard(material.BuildContext context, RedisInfoSections info) {
    final usedHuman = sectionValue(info, 'Memory', 'used_memory_human') ?? '—';
    final peakHuman = sectionValue(info, 'Memory', 'used_memory_peak_human') ?? '—';
    final frag = sectionDouble(info, 'Memory', 'mem_fragmentation_ratio') ?? 0.0;
    final rss = sectionValue(info, 'Memory', 'used_memory_rss_human') ?? '—';
    return _card(
      context,
      'Memory',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Used memory', usedHuman),
          _row(context, 'Peak', peakHuman),
          _row(context, 'RSS', rss),
          _row(context, 'Fragmentation', '${frag.toStringAsFixed(2)}x'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _statsCard(material.BuildContext context, RedisInfoSections info) {
    final ops = sectionInt(info, 'Stats', 'instantaneous_ops_per_sec') ?? 0;
    final totalOps = sectionInt(info, 'Stats', 'total_commands_processed');
    final keyspaceHits = sectionInt(info, 'Stats', 'keyspace_hits') ?? 0;
    final keyspaceMisses = sectionInt(info, 'Stats', 'keyspace_misses') ?? 0;
    final total = keyspaceHits + keyspaceMisses;
    final hitRate = total > 0 ? (keyspaceHits / total * 100).toStringAsFixed(1) : '—';
    return _card(
      context,
      'Stats',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Ops/s', '$ops'),
          if (totalOps != null) _row(context, 'Total commands', '$totalOps'),
          _row(context, 'Keyspace hits', '$keyspaceHits'),
          _row(context, 'Keyspace misses', '$keyspaceMisses'),
          _row(context, 'Hit rate', '$hitRate%'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _keyspaceCard(material.BuildContext context, RedisInfoSections info) {
    final hits = sectionInt(info, 'Stats', 'keyspace_hits') ?? 0;
    final misses = sectionInt(info, 'Stats', 'keyspace_misses') ?? 0;
    final total = hits + misses;
    final hitPct = total > 0 ? (hits / total * 100).toStringAsFixed(1) : '—';
    return _card(
      context,
      'Keyspace hits / misses',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Hits', '$hits'),
          _row(context, 'Misses', '$misses'),
          _row(context, 'Hit rate', '$hitPct%'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _cpuCard(material.BuildContext context, RedisInfoSections info) {
    final sys = sectionDouble(info, 'CPU', 'used_cpu_sys_main_thread');
    final user = sectionDouble(info, 'CPU', 'used_cpu_user_main_thread');
    return _card(
      context,
      'CPU (main thread)',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          if (sys != null) _row(context, 'System', sys.toStringAsFixed(2)),
          if (user != null) _row(context, 'User', user.toStringAsFixed(2)),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _sectionCard(material.BuildContext context, String title, Map<String, String>? data, {List<String>? keys}) {
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    final entries = keys != null
        ? keys.map((k) => MapEntry(k, data[k])).where((e) => e.value != null).map((e) => MapEntry(e.key, e.value as String)).toList()
        : data.entries.toList();
    if (entries.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      title,
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [for (final e in entries) _row(context, e.key, e.value)],
      ),
    );
  }

  material.Widget _errorStatsCard(material.BuildContext context, RedisInfoSections info) {
    final data = info['Errorstats'];
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      'Error stats',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [for (final e in data.entries) _row(context, e.key, e.value)],
      ),
    );
  }

  material.Widget _row(material.BuildContext context, String key, String value) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(vertical: 4),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.SizedBox(width: 160, child: Text(key).muted().small()),
          material.Expanded(child: material.SelectableText(value, style: material.TextStyle(fontSize: 13, color: cs.foreground))),
        ],
      ),
    );
  }
}
