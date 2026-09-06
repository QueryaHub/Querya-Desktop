import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_server_stats.dart';
import 'package:querya_desktop/core/motion/ticker_gated_polling.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/util/deep_collection_equals.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _pollInterval = Duration(seconds: 5);
const _summaryChipHeight = 88.0;

/// Live dashboard of server statistics reported by an extension driver (Block D).
///
/// Periodically queries [ExtensionDriverSession.getServerStats] and renders
/// server version, uptime, memory usage, active connections/queries, and database sizes.
class ExtensionStatsView extends material.StatefulWidget {
  const ExtensionStatsView({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<ExtensionStatsView> createState() => _ExtensionStatsViewState();
}

class _ExtensionStatsViewState extends material.State<ExtensionStatsView> {
  ExtensionServerStats? _stats;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExtensionStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _timer?.cancel();
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _stats = null;
    });
    try {
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
    try {
      final stats = await ExtensionDriverSession.instance
          .getServerStats(widget.connectionRow);
      if (!mounted) return;
      if (!replaceIfChanged(_stats, stats, (v) => _stats = v)) {
        if (_loading) setState(() => _loading = false);
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
    try {
      final stats = await ExtensionDriverSession.instance
          .getServerStats(widget.connectionRow);
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
    _timer = syncTickerGatedPeriodicTimer(
      context: context,
      timer: _timer,
      shouldRun: !_loading && _error == null,
      interval: _pollInterval,
      onTick: () => unawaited(_onPollTick()),
    );

    final cs = Theme.of(context).colorScheme;

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
            const Text('Loading server statistics...').muted().small(),
          ],
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
                    if (stats.databaseSizes.isNotEmpty) ...[
                      _databasesCard(context, stats),
                      const Gap(24),
                    ],
                    if (stats.extraMetrics.isNotEmpty)
                      _extraMetricsCard(context, stats),
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
                      child: material.Icon(material.Icons.storage_rounded,
                          size: 28, color: cs.primary),
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
                          Text('${widget.connectionRow.host ?? 'Extension Driver'}:${widget.connectionRow.port ?? ''}')
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
      material.BuildContext context, ExtensionServerStats stats) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final versionFull = stats.serverVersion ?? '—';
    final uptimeSec = stats.uptimeSeconds;
    final uptimeStr = uptimeSec == null
        ? '—'
        : _formatUptime(Duration(seconds: uptimeSec));
    final activeConn = stats.activeConnections?.toString() ?? '—';
    final activeQueries = stats.activeQueries?.toString() ?? '—';
    final memStr = stats.memoryUsageBytes == null || stats.memoryUsageBytes == 0
        ? '—'
        : _formatBytes(stats.memoryUsageBytes!);

    final chips = <({String label, String value, material.IconData icon})>[
      (
        label: 'Version',
        value: versionFull,
        icon: material.Icons.info_outline_rounded,
      ),
      (
        label: 'Uptime',
        value: uptimeStr,
        icon: material.Icons.schedule_rounded,
      ),
      (
        label: 'Active Connections',
        value: activeConn,
        icon: material.Icons.link_rounded,
      ),
      (
        label: 'Active Queries',
        value: activeQueries,
        icon: material.Icons.bolt_rounded,
      ),
      (
        label: 'Memory Usage',
        value: memStr,
        icon: material.Icons.memory_rounded,
      ),
    ];

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth < 650
            ? 2
            : (constraints.maxWidth < 1000 ? 3 : 5);
        return GridView(
          shrinkWrap: true,
          physics: const material.NeverScrollableScrollPhysics(),
          gridDelegate: material.SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: _summaryChipHeight,
          ),
          children: [
            for (final c in chips) _buildChip(cs, c),
          ],
        );
      },
    );
  }

  material.Widget _buildChip(
      shadcn.ColorScheme cs, ({String label, String value, material.IconData icon}) chip) {
    return Card(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: material.Row(
        children: [
          material.Container(
            padding: const material.EdgeInsets.all(8),
            decoration: material.BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: material.BorderRadius.circular(8),
            ),
            child: material.Icon(chip.icon, size: 20, color: cs.primary),
          ),
          const Gap(14),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisAlignment: material.MainAxisAlignment.center,
              children: [
                Text(chip.label).muted().small(),
                const Gap(2),
                material.Text(
                  chip.value,
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
    );
  }

  material.Widget _databasesCard(
      material.BuildContext context, ExtensionServerStats stats) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final sizes = stats.databaseSizes;
    final totalBytes = sizes.values.fold<int>(0, (a, b) => a + b);
    final sorted = sizes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      padding: const material.EdgeInsets.all(20),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Row(
            children: [
              material.Icon(material.Icons.storage_rounded,
                  size: 20, color: cs.primary),
              const Gap(10),
              const Text('Databases & Sizes').large().semiBold(),
              const Spacer(),
              Text('Total: ${_formatBytes(totalBytes)}').muted().small(),
            ],
          ),
          const Gap(16),
          material.Table(
            columnWidths: const {
              0: material.FlexColumnWidth(2),
              1: material.FlexColumnWidth(1),
              2: material.FlexColumnWidth(3),
            },
            children: [
              material.TableRow(
                decoration: material.BoxDecoration(
                  border: material.Border(
                      bottom: material.BorderSide(
                          color: cs.border, width: 1)),
                ),
                children: [
                  material.Padding(
                    padding: const material.EdgeInsets.only(bottom: 8),
                    child: const Text('Database').muted().small().semiBold(),
                  ),
                  material.Padding(
                    padding: const material.EdgeInsets.only(bottom: 8),
                    child: const Text('Size').muted().small().semiBold(),
                  ),
                  material.Padding(
                    padding: const material.EdgeInsets.only(bottom: 8),
                    child: const Text('Distribution').muted().small().semiBold(),
                  ),
                ],
              ),
              ...sorted.map((entry) {
                final pct = totalBytes > 0
                    ? (entry.value / totalBytes)
                    : 0.0;
                return material.TableRow(
                  children: [
                    material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 10),
                      child: Text(entry.key).small().semiBold(),
                    ),
                    material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 10),
                      child: Text(_formatBytes(entry.value)).small(),
                    ),
                    material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 10),
                      child: material.Row(
                        children: [
                          material.Expanded(
                            child: material.ClipRRect(
                              borderRadius: material.BorderRadius.circular(4),
                              child: material.LinearProgressIndicator(
                                value: pct,
                                backgroundColor: cs.secondary,
                                color: cs.primary,
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const Gap(10),
                          material.SizedBox(
                            width: 48,
                            child: Text('${(pct * 100).toStringAsFixed(1)}%')
                                .small()
                                .muted(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  material.Widget _extraMetricsCard(
      material.BuildContext context, ExtensionServerStats stats) {
    final cs = shadcn.Theme.of(context).colorScheme;
    final extra = stats.extraMetrics.entries.toList();

    return Card(
      padding: const material.EdgeInsets.all(20),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Row(
            children: [
              material.Icon(material.Icons.analytics_rounded,
                  size: 20, color: cs.primary),
              const Gap(10),
              const Text('Extra Metrics').large().semiBold(),
            ],
          ),
          const Gap(16),
          material.Wrap(
            spacing: 16,
            runSpacing: 16,
            children: extra.map((e) {
              return material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: material.BoxDecoration(
                  color: cs.secondary.withValues(alpha: 0.4),
                  borderRadius: material.BorderRadius.circular(8),
                  border: material.Border.all(color: cs.border),
                ),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    Text(e.key).muted().small(),
                    const Gap(4),
                    Text('${e.value}').semiBold(),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    double val = bytes.toDouble();
    int unit = -1;
    while (val >= 1024 && unit < units.length - 1) {
      val /= 1024;
      unit++;
    }
    return '${val.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }

  String _formatUptime(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h ${mins}m';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}
