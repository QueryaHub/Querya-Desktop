import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _defaultAutoRefresh = Duration(seconds: 3);
const _summaryChipHeight = 88.0;
const _gridCardMinHeight = 220.0;

class MongoStatsView extends material.StatefulWidget {
  const MongoStatsView({
    super.key,
    required this.connectionRow,
    this.connection,
    this.onBack,
  });

  final ConnectionRow connectionRow;

  /// An already-open [MongoConnection]. When provided the view re-uses it
  /// instead of creating (and potentially killing) a shared one.
  final MongoConnection? connection;

  /// Called when the user taps the "back to explorer" button.
  final material.VoidCallback? onBack;

  @override
  material.State<MongoStatsView> createState() => _MongoStatsViewState();
}

class _MongoStatsViewState extends material.State<MongoStatsView> {
  MongoConnection? _connection;
  Map<String, dynamic>? _serverStatus;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  /// `null` = auto-refresh off. Default matches previous 3s polling.
  Duration? _autoRefreshInterval = _defaultAutoRefresh;

  DateTime? _lastFetchedAt;
  bool _manualRefreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MongoStatsView oldWidget) {
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

  /// Clears the local connection reference (pooled socket stays in [MongoService]).
  void _disconnectCurrent() {
    _connection = null;
  }

  Future<void> _load() async {
    _timer?.cancel();
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _serverStatus = null;
    });
    try {
      // Re-use the connection supplied by the parent when available.
      final supplied = widget.connection;
      final MongoConnection conn;
      if (supplied != null && supplied.isConnected) {
        conn = supplied;
      } else {
        conn =
            await MongoService.instance.ensureConnected(widget.connectionRow);
      }
      if (!mounted) {
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
    if (c == null || !c.isConnected) return;
    try {
      final status = await MongoService.instance.executeCommand(
        c,
        'admin',
        {'serverStatus': 1},
      );
      if (!mounted) return;
      final changed =
          replaceIfChanged(_serverStatus, status, (v) => _serverStatus = v);
      if (!changed && !_loading) return;
      setState(() {
        _loading = false;
        if (changed) _lastFetchedAt = DateTime.now();
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

  /// Fetches [serverStatus] only (no full reconnect). Use from toolbar / pull-to-refresh.
  Future<void> _refreshNow() async {
    final c = _connection;
    if (c == null || !c.isConnected) {
      await _load();
      return;
    }
    setState(() => _manualRefreshing = true);
    try {
      await _fetch();
    } finally {
      if (mounted) setState(() => _manualRefreshing = false);
    }
  }

  Future<void> _pollTick() async {
    final c = _connection;
    if (c == null || !c.isConnected) return;
    try {
      final status = await MongoService.instance.executeCommand(
        c,
        'admin',
        {'serverStatus': 1},
      );
      if (!mounted) return;
      if (!replaceIfChanged(_serverStatus, status, (v) => _serverStatus = v)) {
        return;
      }
      setState(() => _lastFetchedAt = DateTime.now());
    } catch (_) {
      // Keep last good snapshot on transient errors during auto-refresh.
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final interval = _autoRefreshInterval;
    if (interval == null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_pollTick()));
  }

  String _formatClock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  material.Widget build(material.BuildContext context) {
    final interval = _autoRefreshInterval;
    if (interval != null) {
      _timer = syncTickerGatedPeriodicTimer(
        context: context,
        timer: _timer,
        shouldRun: !_loading && _connection != null,
        interval: interval,
        onTick: () => unawaited(_pollTick()),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }

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

    final status = _serverStatus;
    if (status == null) {
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
              const Text('serverStatus returned no data.').muted().small(),
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
        onRefresh: _refreshNow,
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
                _summaryChips(context, status),
                const Gap(24),
                _gridRow(
                  _memoryCard(context, status),
                  _operationsCard(context, status),
                ),
                const Gap(16),
                _gridRow(
                  _connectionsCard(context, status),
                  _networkCard(context, status),
                ),
                const Gap(24),
                _sectionCard(context, 'Server', _extractServerInfo(status)),
                const Gap(12),
                material.LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final storage = _extractStorageInfo(status);
                    final replication = _extractReplicationInfo(status);
                    if (!wide) {
                      return material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.stretch,
                        children: [
                          _sectionCard(context, 'Storage', storage),
                          const Gap(12),
                          _sectionCard(context, 'Replication', replication),
                        ],
                      );
                    }
                    return material.Row(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        material.Expanded(
                          child: _sectionCard(context, 'Storage', storage),
                        ),
                        const Gap(16),
                        material.Expanded(
                          child:
                              _sectionCard(context, 'Replication', replication),
                        ),
                      ],
                    );
                  },
                ),
                const Gap(12),
                _sectionCard(
                    context, 'WiredTiger', _extractWiredTigerInfo(status)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _header(material.BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final last = _lastFetchedAt;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Row(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Container(
              padding: const material.EdgeInsets.all(10),
              decoration: material.BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: material.BorderRadius.circular(12),
              ),
              child: material.Icon(material.Icons.eco_rounded,
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
                  Text('${widget.connectionRow.host ?? 'localhost'}:${widget.connectionRow.port ?? 27017}')
                      .muted()
                      .small(),
                  if (last != null) ...[
                    const Gap(4),
                    Text('Last updated ${_formatClock(last)}').muted().xSmall(),
                  ],
                ],
              ),
            ),
          ],
        ),
        const Gap(12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: material.WrapAlignment.end,
          crossAxisAlignment: material.WrapCrossAlignment.center,
          children: [
            if (widget.onBack != null)
              OutlineButton(
                onPressed: widget.onBack,
                leading: const material.Icon(material.Icons.grid_view_rounded,
                    size: 18),
                child: const Text('Explorer'),
              ),
            OutlineButton(
              onPressed: _manualRefreshing ? null : _refreshNow,
              leading: _manualRefreshing
                  ? const material.SizedBox(
                      width: 16,
                      height: 16,
                      child: material.CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const material.Icon(material.Icons.refresh_rounded,
                      size: 18),
              child: const Text('Refresh now'),
            ),
            material.SizedBox(
              width: 132,
              child: QueryaDropdown<Duration?>(
                expandToParent: true,
                value: _autoRefreshInterval,
                items: const [
                  QueryaDropdownItem<Duration?>(
                      value: null, label: 'Auto: off'),
                  QueryaDropdownItem(
                      value: Duration(seconds: 3), label: 'Auto: 3 s'),
                  QueryaDropdownItem(
                      value: Duration(seconds: 10), label: 'Auto: 10 s'),
                  QueryaDropdownItem(
                      value: Duration(seconds: 30), label: 'Auto: 30 s'),
                  QueryaDropdownItem(
                      value: Duration(seconds: 60), label: 'Auto: 60 s'),
                ],
                onSelected: (value) {
                  setState(() => _autoRefreshInterval = value);
                  _startTimer();
                },
              ),
            ),
          ],
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

  material.Widget _summaryChips(
      material.BuildContext context, Map<String, dynamic> status) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final version = _getString(status, 'version') ?? '—';
    final uptime = _formatUptime(_getInt(status, 'uptime') ?? 0);
    final connections = _getNestedInt(status, 'connections', 'current') ?? 0;
    final available = _getNestedInt(status, 'connections', 'available') ?? 0;
    final ops = _getNestedInt(status, 'opcounters', 'query') ?? 0;
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
        chip('Connections', '$connections / $available',
            material.Icons.people_outline_rounded),
        const Gap(12),
        chip('Queries', '$ops', material.Icons.speed_rounded),
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
      material.BuildContext context, Map<String, dynamic> status) {
    final mem = status['mem'] as Map<String, dynamic>?;
    final resident = _getInt(mem, 'resident') ?? 0;
    final virtual = _getInt(mem, 'virtual') ?? 0;
    final mapped = _getInt(mem, 'mapped') ?? 0;
    final mappedWithJournal = _getInt(mem, 'mappedWithJournal') ?? 0;
    return _card(
      context,
      'Memory',
      _metricList(
        context,
        [
          _metricRow(context, 'Resident', _formatBytes(resident)),
          _metricRow(context, 'Virtual', _formatBytes(virtual)),
          _metricRow(context, 'Mapped', _formatBytes(mapped)),
          _metricRow(
              context, 'Mapped + Journal', _formatBytes(mappedWithJournal)),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _operationsCard(
      material.BuildContext context, Map<String, dynamic> status) {
    final opcounters = status['opcounters'] as Map<String, dynamic>?;
    final inserts = _getInt(opcounters, 'insert') ?? 0;
    final queries = _getInt(opcounters, 'query') ?? 0;
    final updates = _getInt(opcounters, 'update') ?? 0;
    final deletes = _getInt(opcounters, 'delete') ?? 0;
    return _card(
      context,
      'Operations',
      _metricList(
        context,
        [
          _metricRow(context, 'Inserts', '$inserts'),
          _metricRow(context, 'Queries', '$queries'),
          _metricRow(context, 'Updates', '$updates'),
          _metricRow(context, 'Deletes', '$deletes'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _connectionsCard(
      material.BuildContext context, Map<String, dynamic> status) {
    final connections = status['connections'] as Map<String, dynamic>?;
    final current = _getInt(connections, 'current') ?? 0;
    final available = _getInt(connections, 'available') ?? 0;
    final active =
        _getNestedInt(status, 'globalLock', 'activeClients', 'total') ?? 0;
    return _card(
      context,
      'Connections',
      _metricList(
        context,
        [
          _metricRow(context, 'Current', '$current'),
          _metricRow(context, 'Available', '$available'),
          _metricRow(context, 'Active clients', '$active'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _networkCard(
      material.BuildContext context, Map<String, dynamic> status) {
    final network = status['network'] as Map<String, dynamic>?;
    final bytesIn = _getInt(network, 'bytesIn') ?? 0;
    final bytesOut = _getInt(network, 'bytesOut') ?? 0;
    final numRequests = _getInt(network, 'numRequests') ?? 0;
    return _card(
      context,
      'Network',
      _metricList(
        context,
        [
          _metricRow(context, 'Bytes in', _formatBytes(bytesIn)),
          _metricRow(context, 'Bytes out', _formatBytes(bytesOut)),
          _metricRow(context, 'Requests', '$numRequests'),
        ],
        stretch: true,
      ),
      minHeight: _gridCardMinHeight,
      stretchBody: true,
    );
  }

  material.Widget _sectionCard(
      material.BuildContext context, String title, Map<String, String>? data) {
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      title,
      _twoColumnMetrics(
        context,
        [ for (final e in data.entries) MapEntry(e.key, e.value) ],
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

  // Helper methods to extract data from serverStatus
  String? _getString(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    return v?.toString();
  }

  int? _getInt(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  int? _getNestedInt(Map<String, dynamic>? map, String key1, String key2,
      [String? key3]) {
    final m1 = map?[key1] as Map<String, dynamic>?;
    if (m1 == null) return null;
    if (key3 != null) {
      final m2 = m1[key2] as Map<String, dynamic>?;
      if (m2 == null) return null;
      final v = m2[key3];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }
    final v = m1[key2];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Map<String, String> _extractServerInfo(Map<String, dynamic> status) {
    final result = <String, String>{};
    if (status['host'] != null) result['Host'] = status['host'].toString();
    if (status['version'] != null) {
      result['Version'] = status['version'].toString();
    }
    if (status['process'] != null) {
      result['Process'] = status['process'].toString();
    }
    final uptime = _getInt(status, 'uptime');
    if (uptime != null) {
      result['Uptime'] = '${_formatUptime(uptime)} ($uptime s)';
    }
    return result;
  }

  Map<String, String> _extractStorageInfo(Map<String, dynamic> status) {
    final result = <String, String>{};
    final dur = status['dur'] as Map<String, dynamic>?;
    if (dur != null) {
      if (dur['commitsInWriteLock'] != null) {
        result['Commits in write lock'] = dur['commitsInWriteLock'].toString();
      }
    }
    return result;
  }

  Map<String, String> _extractReplicationInfo(Map<String, dynamic> status) {
    final result = <String, String>{};
    final repl = status['repl'] as Map<String, dynamic>?;
    if (repl != null) {
      if (repl['setName'] != null) {
        result['Replica set'] = repl['setName'].toString();
      }
      if (repl['ismaster'] != null) {
        result['Is master'] = repl['ismaster'].toString();
      }
      if (repl['secondary'] != null) {
        result['Secondary'] = repl['secondary'].toString();
      }
    }
    return result;
  }

  Map<String, String> _extractWiredTigerInfo(Map<String, dynamic> status) {
    final result = <String, String>{};
    final wiredTiger = status['wiredTiger'] as Map<String, dynamic>?;
    if (wiredTiger != null) {
      final cache = wiredTiger['cache'] as Map<String, dynamic>?;
      if (cache != null) {
        final maxSize = _getInt(cache, 'maximum bytes configured');
        if (maxSize != null) result['Max cache size'] = _formatBytes(maxSize);
        final usedSize = _getInt(cache, 'bytes currently in the cache');
        if (usedSize != null) result['Cache used'] = _formatBytes(usedSize);
      }
    }
    return result;
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
