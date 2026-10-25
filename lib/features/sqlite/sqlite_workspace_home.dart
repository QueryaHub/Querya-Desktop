import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/core/storage/local_db.dart' show ConnectionRow;
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/sqlite/sqlite_overview_tab.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_tx_guard.dart';
import 'package:querya_desktop/features/sqlite/sqlite_sql_workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

class SqliteWorkspaceHome extends material.StatefulWidget {
  const SqliteWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.sqlTabRequestToken = 0,
    this.lastSelectedSqliteObject,
    this.onRestoreLastSelectedObject,
    this.onOpenTable,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final int sqlTabRequestToken;
  final bool isReadOnly;

  /// Remembers the last visited table/view for 1-click return.
  final ({String name, SqliteObjectKind kind})? lastSelectedSqliteObject;
  final VoidCallback? onRestoreLastSelectedObject;

  /// Opens a table from the Overview page.
  final void Function(String name)? onOpenTable;

  @override
  material.State<SqliteWorkspaceHome> createState() =>
      _SqliteWorkspaceHomeState();
}

class _SqliteWorkspaceHomeState extends material.State<SqliteWorkspaceHome> {
  int _tab = 0;
  late final material.ValueNotifier<bool?> _sqlTxNotifier;
  int _lastAppliedSqlTabToken = 0;

  @override
  void initState() {
    super.initState();
    _sqlTxNotifier = material.ValueNotifier<bool?>(null);
    _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
  }

  @override
  void didUpdateWidget(covariant SqliteWorkspaceHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
      return;
    }
    final t = widget.sqlTabRequestToken;
    if (t > _lastAppliedSqlTabToken) {
      _lastAppliedSqlTabToken = t;
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _tab = 1);
      });
    }
  }

  @override
  void dispose() {
    _sqlTxNotifier.dispose();
    super.dispose();
  }

  Future<void> _selectTab(int i) async {
    if (i == _tab) return;
    if (_tab == 1 && i == 0 && _sqlTxNotifier.value == true) {
      final ok = await confirmLeaveOpenSqliteTransaction(context);
      if (!ok) return;
    }
    setState(() => _tab = i);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 44),
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: colors.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              const Text('SQLite').semiBold().small(),
              if (widget.isReadOnly) ...[
                const Gap(6),
                material.Icon(
                  material.Icons.lock_outline_rounded,
                  size: 14,
                  color: colors.mutedForeground,
                ),
              ],
              if (widget.lastSelectedSqliteObject != null &&
                  widget.onRestoreLastSelectedObject != null) ...[
                const Gap(12),
                QueryaButton.secondary(
                  label: 'Return to ${widget.lastSelectedSqliteObject!.name}',
                  icon: material.Icons.table_chart_outlined,
                  onPressed: widget.onRestoreLastSelectedObject,
                  size: QueryaControlSize.sm,
                ),
              ],
              material.Expanded(
                child: material.Align(
                  alignment: material.Alignment.centerRight,
                  child: QueryaTabStrip(
                    labels: const ['Overview', 'SQL'],
                    selectedIndex: _tab,
                    onSelected: _selectTab,
                  ),
                ),
              ),
            ],
          ),
        ),
        const QueryaDivider(height: 1),
        Expanded(
          child: QueryaCrossFadeStack(
            index: _tab,
            children: [
              SqliteOverviewTab(
                key: ValueKey('sqlite_overview_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                onOpenTable: widget.onOpenTable,
              ),
              SqliteSqlWorkspace(
                key: ValueKey('sqlite_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                transactionOpenNotifier: _sqlTxNotifier,
                isReadOnly: widget.isReadOnly,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
