import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Summary when a MySQL connection is selected without a tree object.
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
  String? _version;
  int? _databaseCount;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MysqlStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _disconnect();
      _load();
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  void _disconnect() {
    _lease?.release();
    _lease = null;
  }

  Future<void> _load() async {
    _disconnect();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _version = null;
      _databaseCount = null;
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
      final v = await lease.connection.serverVersion();
      final dbs = await lease.connection.listDatabases();
      if (!mounted) return;
      setState(() {
        _version = v;
        _databaseCount = dbs.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.SizedBox(
              width: 28,
              height: 28,
              child: material.CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
            const Gap(12),
            const Text('Loading server info...').muted().small(),
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
              material.Icon(
                material.Icons.error_outline_rounded,
                size: 48,
                color: cs.destructive,
              ),
              const Gap(16),
              const Text('Could not load server info').large().semiBold(),
              const Gap(8),
              material.SelectableText(
                _error!,
                style: material.TextStyle(
                  color: cs.mutedForeground,
                  fontSize: 13,
                ),
              ),
              const Gap(24),
              OutlineButton(
                onPressed: _load,
                leading: const material.Icon(
                  material.Icons.refresh_rounded,
                  size: 18,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.all(24),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          const Text('Server').large().semiBold(),
          const Gap(16),
          material.Container(
            width: double.infinity,
            padding: const material.EdgeInsets.all(16),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.35),
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(color: cs.border.withValues(alpha: 0.4)),
            ),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                const Text('Version').small().muted(),
                const Gap(4),
                material.SelectableText(
                  _version ?? '—',
                  style: material.TextStyle(
                    fontSize: 13,
                    color: cs.foreground,
                  ),
                ),
                const Gap(16),
                const Text('User databases (approx.)').small().muted(),
                const Gap(4),
                Text(
                  '${_databaseCount ?? 0}',
                  style: material.TextStyle(
                    fontSize: 20,
                    fontWeight: material.FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
