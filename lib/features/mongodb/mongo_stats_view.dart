import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 3);
const _summaryChipHeight = 72.0;
const _gridCardHeight = 220.0;

class MongoStatsView extends material.StatefulWidget {
  const MongoStatsView({super.key, required this.connectionRow});
  final ConnectionRow connectionRow;

  @override
  material.State<MongoStatsView> createState() => _MongoStatsViewState();
}

class _MongoStatsViewState extends material.State<MongoStatsView> {
  MongoConnection? _connection;
  Map<String, dynamic>? _serverStatus;
  bool _loading = true;
  String? _error;
  Timer? _timer;

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

  /// Safely disconnects and clears the current MongoDB connection.
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
      _serverStatus = null;
    });
    try {
      final conn = MongoService.instance.createConnection(widget.connectionRow);
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
    if (c == null || !c.isConnected) return;
    try {
      final status = await MongoService.instance.executeCommand(
        c,
        'admin',
        {'serverStatus': 1},
      );
      if (!mounted) return;
      setState(() {
        _serverStatus = status;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) async {
      final c = _connection;
      if (c == null || !c.isConnected) return;
      try {
        final status = await MongoService.instance.executeCommand(
          c,
          'admin',
          {'serverStatus': 1},
        );
        if (!mounted) return;
        setState(() => _serverStatus = status);
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
              material.Icon(material.Icons.error_outline_rounded, size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
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

    final status = _serverStatus;
    if (status == null) return material.Container(color: cs.background);

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
                _summaryChips(context, status),
                const Gap(24),
                material.Row(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    material.Expanded(child: _memoryCard(context, status)),
                    const Gap(16),
                    material.Expanded(child: _operationsCard(context, status)),
                  ],
                ),
                const Gap(16),
                material.Row(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    material.Expanded(child: _connectionsCard(context, status)),
                    const Gap(16),
                    material.Expanded(child: _networkCard(context, status)),
                  ],
                ),
                const Gap(24),
                _sectionCard(context, 'Server', _extractServerInfo(status)),
                const Gap(12),
                _sectionCard(context, 'Storage', _extractStorageInfo(status)),
                const Gap(12),
                _sectionCard(context, 'Replication', _extractReplicationInfo(status)),
                const Gap(12),
                _sectionCard(context, 'WiredTiger', _extractWiredTigerInfo(status)),
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
          child: material.Icon(material.Icons.eco_rounded, size: 28, color: cs.primary),
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

  material.Widget _summaryChips(material.BuildContext context, Map<String, dynamic> status) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final version = _getString(status, 'version') ?? '—';
    final uptime = _getInt(status, 'uptime') ?? 0;
    final uptimeDays = (uptime / 86400).toStringAsFixed(1);
    final connections = _getNestedInt(status, 'connections', 'current') ?? 0;
    final maxConnections = _getNestedInt(status, 'connections', 'available') ?? 0;
    final ops = _getNestedInt(status, 'opcounters', 'query') ?? 0;
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
        chip('Uptime', '$uptimeDays days', material.Icons.schedule_rounded),
        const Gap(12),
        chip('Connections', '$connections / $maxConnections', material.Icons.people_outline_rounded),
        const Gap(12),
        chip('Queries', '$ops', material.Icons.speed_rounded),
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

  material.Widget _memoryCard(material.BuildContext context, Map<String, dynamic> status) {
    final mem = status['mem'] as Map<String, dynamic>?;
    final resident = _getInt(mem, 'resident') ?? 0;
    final virtual = _getInt(mem, 'virtual') ?? 0;
    final mapped = _getInt(mem, 'mapped') ?? 0;
    final mappedWithJournal = _getInt(mem, 'mappedWithJournal') ?? 0;
    return _card(
      context,
      'Memory',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Resident', _formatBytes(resident)),
          _row(context, 'Virtual', _formatBytes(virtual)),
          _row(context, 'Mapped', _formatBytes(mapped)),
          _row(context, 'Mapped + Journal', _formatBytes(mappedWithJournal)),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _operationsCard(material.BuildContext context, Map<String, dynamic> status) {
    final opcounters = status['opcounters'] as Map<String, dynamic>?;
    final inserts = _getInt(opcounters, 'insert') ?? 0;
    final queries = _getInt(opcounters, 'query') ?? 0;
    final updates = _getInt(opcounters, 'update') ?? 0;
    final deletes = _getInt(opcounters, 'delete') ?? 0;
    return _card(
      context,
      'Operations',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Inserts', '$inserts'),
          _row(context, 'Queries', '$queries'),
          _row(context, 'Updates', '$updates'),
          _row(context, 'Deletes', '$deletes'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _connectionsCard(material.BuildContext context, Map<String, dynamic> status) {
    final connections = status['connections'] as Map<String, dynamic>?;
    final current = _getInt(connections, 'current') ?? 0;
    final available = _getInt(connections, 'available') ?? 0;
    final active = _getNestedInt(status, 'globalLock', 'activeClients', 'total') ?? 0;
    return _card(
      context,
      'Connections',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Current', '$current'),
          _row(context, 'Available', '$available'),
          _row(context, 'Active clients', '$active'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _networkCard(material.BuildContext context, Map<String, dynamic> status) {
    final network = status['network'] as Map<String, dynamic>?;
    final bytesIn = _getInt(network, 'bytesIn') ?? 0;
    final bytesOut = _getInt(network, 'bytesOut') ?? 0;
    final numRequests = _getInt(network, 'numRequests') ?? 0;
    return _card(
      context,
      'Network',
      material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Bytes in', _formatBytes(bytesIn)),
          _row(context, 'Bytes out', _formatBytes(bytesOut)),
          _row(context, 'Requests', '$numRequests'),
        ],
      ),
      height: _gridCardHeight,
    );
  }

  material.Widget _sectionCard(material.BuildContext context, String title, Map<String, String>? data) {
    if (data == null || data.isEmpty) return const material.SizedBox.shrink();
    return _card(
      context,
      title,
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

  int? _getNestedInt(Map<String, dynamic>? map, String key1, String key2, [String? key3]) {
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
    if (status['version'] != null) result['Version'] = status['version'].toString();
    if (status['process'] != null) result['Process'] = status['process'].toString();
    final uptime = _getInt(status, 'uptime');
    if (uptime != null) {
      final days = (uptime / 86400).toStringAsFixed(1);
      result['Uptime'] = '$days days ($uptime seconds)';
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
      if (repl['setName'] != null) result['Replica set'] = repl['setName'].toString();
      if (repl['ismaster'] != null) result['Is master'] = repl['ismaster'].toString();
      if (repl['secondary'] != null) result['Secondary'] = repl['secondary'].toString();
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
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
