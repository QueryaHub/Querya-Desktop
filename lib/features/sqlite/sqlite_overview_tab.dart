import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _summaryChipHeight = 88.0;

/// Overview tab (`Overview / Database Info`) for SQLite workspace home.
class SqliteOverviewTab extends material.StatefulWidget {
  const SqliteOverviewTab({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  material.State<SqliteOverviewTab> createState() => _SqliteOverviewTabState();
}

class _SqliteOverviewTabState extends material.State<SqliteOverviewTab> {
  SqliteLease? _lease;
  SqliteConnection? get _connection => _lease?.connection;

  Map<String, dynamic>? _overview;
  List<String> _tables = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SqliteOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _disconnectCurrent();
      _load();
    }
  }

  @override
  void dispose() {
    _disconnectCurrent();
    super.dispose();
  }

  void _disconnectCurrent() {
    _lease?.release();
    _lease = null;
  }

  Future<void> _load() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _overview = null;
      _tables = [];
    });
    try {
      final lease = await SqliteService.instance.acquire(widget.connectionRow);
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch();
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
      final info = await c.databaseOverview();
      final tbls = await c.listTables();
      if (!mounted) return;
      setState(() {
        _overview = info;
        _tables = tbls;
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

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    return '${size.toStringAsFixed(idx == 0 ? 0 : 2)} ${units[idx]}';
  }

  int _getFileSizeOnDisk() {
    try {
      final path = widget.connectionRow.host ?? '';
      if (path.isNotEmpty && path != ':memory:') {
        final f = File(path);
        if (f.existsSync()) {
          return f.lengthSync();
        }
      }
    } catch (_) {}
    return 0;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = material.MediaQuery.sizeOf(context).width;

    if (_loading && _overview == null) {
      return material.Center(
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 16,
              height: 16,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(12),
            const Text('Loading database overview...').muted().small(),
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

    final info = _overview;
    if (info == null) return material.Container(color: cs.background);

    final diskSize = _getFileSizeOnDisk();
    final pageCount = info['page_count'] as int? ?? 0;
    final pageSize = info['page_size'] as int? ?? 0;
    final calcSize = pageCount * pageSize;
    final sizeStr = diskSize > 0 ? _formatBytes(diskSize) : _formatBytes(calcSize);
    final versionStr = info['version']?.toString() ?? '—';
    final journalStr = info['journal_mode']?.toString().toUpperCase() ?? '—';

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
                _summaryChips(context, versionStr, sizeStr, journalStr, pageCount, pageSize),
                const Gap(24),
                _tablesCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _header(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.connectionRow.name;
    final path = widget.connectionRow.host ?? 'in-memory';
    return material.Row(
      children: [
        material.Container(
          width: 44,
          height: 44,
          decoration: material.BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: material.BorderRadius.circular(10),
          ),
          child: material.Icon(material.Icons.storage_rounded,
              color: cs.primary, size: 24),
        ),
        const Gap(16),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              material.Row(
                children: [
                  Text(name).large().semiBold(),
                  const Gap(8),
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: material.BoxDecoration(
                      color: cs.muted,
                      borderRadius: material.BorderRadius.circular(4),
                    ),
                    child: const Text('SQLite').xSmall().muted(),
                  ),
                ],
              ),
              const Gap(4),
              material.Text(
                path,
                maxLines: 1,
                overflow: material.TextOverflow.ellipsis,
                style: material.TextStyle(fontSize: 13, color: cs.mutedForeground),
              ),
            ],
          ),
        ),
        OutlineButton(
          onPressed: _fetch,
          leading: const material.Icon(material.Icons.refresh_rounded, size: 16),
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  material.Widget _summaryChips(
    material.BuildContext context,
    String version,
    String size,
    String journal,
    int pageCount,
    int pageSize,
  ) {
    final cs = Theme.of(context).colorScheme;

    material.Widget chip(String label, String value, material.IconData icon) {
      return material.Expanded(
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(minHeight: _summaryChipHeight),
          child: material.Container(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: material.BoxDecoration(
              color: cs.card,
              borderRadius: material.BorderRadius.circular(10),
              border: material.Border.all(color: cs.border.withValues(alpha: 0.5)),
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
        chip('SQLite Version', version, material.Icons.info_outline_rounded),
        const Gap(12),
        chip('Database Size', size, material.Icons.data_usage_rounded),
        const Gap(12),
        chip('Pages / Page Size', '$pageCount / $pageSize B', material.Icons.find_in_page_rounded),
        const Gap(12),
        chip('Journal Mode', journal, material.Icons.history_rounded),
      ],
    );
  }

  material.Widget _tablesCard(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Container(
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(12),
        border: material.Border.all(color: cs.border.withValues(alpha: 0.5)),
      ),
      padding: const material.EdgeInsets.all(20),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Row(
            children: [
              material.Icon(material.Icons.table_chart_rounded,
                  size: 18, color: cs.primary),
              const Gap(8),
              const Text('Tables').semiBold(),
              const Gap(8),
              material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: material.BoxDecoration(
                  color: cs.muted,
                  borderRadius: material.BorderRadius.circular(4),
                ),
                child: Text('${_tables.length}').xSmall().muted(),
              ),
            ],
          ),
          const Gap(16),
          if (_tables.isEmpty)
            material.Padding(
              padding: const material.EdgeInsets.symmetric(vertical: 24),
              child: material.Center(
                child: const Text('No user tables in database.').muted().small(),
              ),
            )
          else
            material.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tables.map((t) {
                return material.Container(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: material.BoxDecoration(
                    color: cs.muted.withValues(alpha: 0.4),
                    borderRadius: material.BorderRadius.circular(6),
                    border: material.Border.all(
                        color: cs.border.withValues(alpha: 0.3)),
                  ),
                  child: material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.Icon(material.Icons.grid_on_rounded,
                          size: 14, color: cs.primary),
                      const Gap(6),
                      Text(t).small(),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
