import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Displays MySQL routine DDL (`SHOW CREATE PROCEDURE` / `SHOW CREATE FUNCTION`).
class MysqlRoutineView extends material.StatefulWidget {
  const MysqlRoutineView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.routineName,
    required this.isFunction,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String routineName;
  final bool isFunction;

  @override
  material.State<MysqlRoutineView> createState() => _MysqlRoutineViewState();
}

class _MysqlRoutineViewState extends material.State<MysqlRoutineView> {
  MysqlLease? _lease;
  bool _loading = true;
  String? _error;
  String? _ddlText;

  @override
  void initState() {
    super.initState();
    _loadRoutine();
  }

  @override
  void didUpdateWidget(covariant MysqlRoutineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.routineName != widget.routineName ||
        oldWidget.isFunction != widget.isFunction) {
      _lease?.release();
      _lease = null;
      _loadRoutine();
    }
  }

  @override
  void dispose() {
    _lease?.release();
    super.dispose();
  }

  Future<void> _loadRoutine() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _ddlText = null;
    });

    try {
      final lease = await MysqlService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: MysqlSessionMode.readOnly,
      );
      _lease = lease;

      final kindCmd = widget.isFunction ? 'FUNCTION' : 'PROCEDURE';
      final rs = await lease.connection
          .execute('SHOW CREATE $kindCmd `${widget.routineName}`');

      if (!mounted) return;
      if (rs.rows.isEmpty) {
        setState(() {
          _error = '$kindCmd `${widget.routineName}` not found.';
          _loading = false;
        });
        return;
      }

      // SHOW CREATE PROCEDURE/FUNCTION usually returns:
      // [Procedure/Function, sql_mode, Create Procedure/Function, ...]
      // The DDL is typically column index 2.
      var ddl = rs.rows.first.colAt(2);
      if (ddl == null || ddl.isEmpty) {
        for (var i = 0; i < rs.rows.first.numOfColumns; i++) {
          final val = rs.rows.first.colAt(i);
          if (val != null &&
              (val.toUpperCase().contains('CREATE PROCEDURE') ||
                  val.toUpperCase().contains('CREATE DEFINER') ||
                  val.toUpperCase().contains('CREATE FUNCTION'))) {
            ddl = val;
            break;
          }
        }
      }

      setState(() {
        _ddlText = ddl ?? rs.rows.first.colAt(1) ?? '-- No definition returned';
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
    final kindTitle = widget.isFunction ? 'Function' : 'Procedure';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Container(
          padding:
              const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.card,
            border: material.Border(
              bottom: material.BorderSide(
                color: theme.colorScheme.border.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: material.Row(
            children: [
              material.Icon(
                material.Icons.functions_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const Gap(8),
              material.Expanded(
                child: Text('$kindTitle · ${widget.database}.${widget.routineName}')
                    .semiBold()
                    .small(),
              ),
              OutlineButton(
                size: ButtonSize.small,
                onPressed: _loading ? null : _loadRoutine,
                leading: const material.Icon(
                  material.Icons.refresh_rounded,
                  size: 14,
                ),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
        if (_loading)
          const material.Expanded(
            child: material.Center(
              child: material.CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          material.Expanded(
            child: VirtualSelectableTextView(
              text: _error!,
              style: material.TextStyle(color: cs.destructive, fontSize: 13),
            ),
          )
        else
          material.Expanded(
            child: VirtualSelectableTextView(
              text: _ddlText ?? '',
              style: const material.TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}
