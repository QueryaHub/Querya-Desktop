import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows [pg_get_functiondef] for each overload of a PostgreSQL function.
class PostgresRoutineView extends material.StatefulWidget {
  const PostgresRoutineView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.routineName,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String routineName;

  @override
  material.State<PostgresRoutineView> createState() =>
      _PostgresRoutineViewState();
}

class _PostgresRoutineViewState extends material.State<PostgresRoutineView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgFunctionOverload> _overloads = [];
  final _scrollController = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant PostgresRoutineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.schema != widget.schema ||
        oldWidget.routineName != widget.routineName) {
      _disconnectCurrent();
      _connectAndLoad();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disconnectCurrent(interruptIfBusy: true);
    super.dispose();
  }

  void _disconnectCurrent({bool interruptIfBusy = false}) {
    if (interruptIfBusy && _loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    _lease = null;
  }

  Future<void> _connectAndLoad() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _overloads = [];
    });
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final conn = lease.connection;
      final list = await conn.getFunctionDefinitions(
        widget.schema,
        widget.routineName,
      );
      if (!mounted) return;
      setState(() {
        _overloads = list;
        _loading = false;
        if (list.isEmpty) {
          _error = 'No function definitions found (check permissions or name).';
        } else {
          _error = null;
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
              const Text('Loading function…').muted().small(),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
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
                const Text('Function').large().semiBold(),
                const Gap(8),
                material.SelectableText(_error!,
                    style: material.TextStyle(
                        color: cs.mutedForeground, fontSize: 13)),
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
                material.Icon(material.Icons.functions_rounded,
                    size: 18, color: cs.primary),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    '${widget.schema}.${widget.routineName}()',
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
                    for (var i = 0; i < _overloads.length; i++) ...[
                      if (i > 0) const Gap(24),
                      if (_overloads.length > 1)
                        material.Padding(
                          padding: const material.EdgeInsets.only(bottom: 8),
                          child: Text(
                            _overloads[i].signature,
                            style: material.TextStyle(
                              fontSize: 12,
                              fontWeight: material.FontWeight.w600,
                              color: cs.foreground,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
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
                          _overloads[i].definition,
                          style: material.TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.45,
                            color: cs.foreground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
