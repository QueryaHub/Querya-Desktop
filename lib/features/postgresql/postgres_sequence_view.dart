import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows [pg_sequences] metadata, current value, and generated DDL.
class PostgresSequenceView extends material.StatefulWidget {
  const PostgresSequenceView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.sequenceName,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String sequenceName;

  @override
  material.State<PostgresSequenceView> createState() =>
      _PostgresSequenceViewState();
}

class _PostgresSequenceViewState extends material.State<PostgresSequenceView> {
  PostgresConnection? _connection;
  bool _loading = true;
  String? _error;
  PostgresSequenceDetails? _details;
  final _scrollController = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant PostgresSequenceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.schema != widget.schema ||
        oldWidget.sequenceName != widget.sequenceName) {
      _disconnectCurrent();
      _connectAndLoad();
    }
  }

  @override
  void dispose() {
    _disconnectCurrent();
    super.dispose();
  }

  void _disconnectCurrent() {
    final conn = _connection;
    _connection = null;
    conn?.disconnect();
  }

  Future<void> _connectAndLoad() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _details = null;
    });
    try {
      final c = widget.connectionRow;
      final conn = PostgresConnection(
        id: c.id ?? 0,
        name: c.name,
        host: c.host ?? 'localhost',
        port: c.port ?? 5432,
        username: c.username,
        password: c.password,
        database: widget.database,
        useSSL: c.useSSL,
      );
      await conn.connect();
      if (!mounted) {
        conn.disconnect();
        return;
      }
      _connection = conn;
      final d = await conn.getSequenceDetails(
        widget.schema,
        widget.sequenceName,
      );
      if (!mounted) return;
      setState(() {
        _details = d;
        _loading = false;
        if (d == null) {
          _error =
              'Sequence not found in pg_sequences (PostgreSQL 10+ required), '
              'or name mismatch.';
        }
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

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              const material.SizedBox(
                width: 28,
                height: 28,
                child: material.CircularProgressIndicator(strokeWidth: 2),
              ),
              const Gap(12),
              const Text('Loading sequence…').muted().small(),
            ],
          ),
        ),
      );
    }

    if (_error != null || _details == null) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.Padding(
            padding: const material.EdgeInsets.all(32),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(material.Icons.error_outline_rounded,
                    size: 48, color: cs.destructive),
                const Gap(16),
                const Text('Sequence').large().semiBold(),
                const Gap(8),
                material.SelectableText(
                  _error ?? 'Unknown error',
                  style: material.TextStyle(
                      color: cs.mutedForeground, fontSize: 13),
                ),
                const Gap(24),
                OutlineButton(
                  onPressed: _connectAndLoad,
                  leading: const material.Icon(material.Icons.refresh_rounded,
                      size: 18),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final d = _details!;

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Container(
            padding: const material.EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: material.BoxDecoration(
              color: cs.card,
              border: material.Border(
                bottom: material.BorderSide(
                    color: cs.border.withValues(alpha: 0.5)),
              ),
            ),
            child: material.Row(
              children: [
                material.Icon(material.Icons.format_list_numbered_rounded,
                    size: 18, color: cs.primary),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    '${d.schema}.${d.name}',
                    style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: material.FontWeight.w600,
                      color: cs.foreground,
                    ),
                    overflow: material.TextOverflow.ellipsis,
                  ),
                ),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _connectAndLoad,
                  leading: const material.Icon(
                      material.Icons.refresh_rounded, size: 14),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          material.Expanded(
            child: material.Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: material.SingleChildScrollView(
                controller: _scrollController,
                padding: const material.EdgeInsets.all(20),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    const Text('Current value').small().semiBold(),
                    const Gap(6),
                    material.SelectableText(
                      d.lastValue,
                      style: material.TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        color: cs.foreground,
                      ),
                    ),
                    const Gap(20),
                    const Text('Properties').small().semiBold(),
                    const Gap(8),
                    _kv(cs, 'last_value', d.lastValue),
                    _kv(cs, 'start_value', d.startValue),
                    _kv(cs, 'min_value', d.minValue),
                    _kv(cs, 'max_value', d.maxValue),
                    _kv(cs, 'increment_by', d.incrementBy),
                    _kv(cs, 'cache_size', d.cacheSize),
                    _kv(cs, 'cycle', d.cycle ? 'yes' : 'no'),
                    const Gap(24),
                    const Text('DDL (approx.)').small().semiBold(),
                    const Gap(8),
                    material.Container(
                      width: double.infinity,
                      padding: const material.EdgeInsets.all(12),
                      decoration: material.BoxDecoration(
                        color: cs.muted.withValues(alpha: 0.15),
                        borderRadius: material.BorderRadius.circular(8),
                        border: material.Border.all(
                          color: cs.border.withValues(alpha: 0.4),
                        ),
                      ),
                      child: material.SelectableText(
                        d.ddl,
                        style: material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                          color: cs.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  material.Widget _kv(dynamic cs, String k, String v) {
    return material.Padding(
      padding: const material.EdgeInsets.only(bottom: 6),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.SizedBox(
            width: 120,
            child: Text(k).muted().xSmall(),
          ),
          material.Expanded(
            child: material.SelectableText(
              v,
              style: material.TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: cs.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
