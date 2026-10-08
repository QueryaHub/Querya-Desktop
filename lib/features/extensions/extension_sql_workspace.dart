import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_driver_recovery_banner.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Table/view selected in the sidebar tree of an extension connection.
typedef ExtensionSelectedObject = ({String database, String name});

/// Execution delegate for plugin/extension database drivers communicating via JSON-RPC.
class ExtensionSqlExecutionDelegate extends SqlExecutionDelegate {
  ExtensionSqlExecutionDelegate({required this.connectionRow});

  final ConnectionRow connectionRow;

  @override
  bool get supportsTransactions => false;

  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) async {
    final sw = Stopwatch()..start();
    final result = await ExtensionDriverSession.instance.query(
      connectionRow,
      sql,
      limit: limit,
    );
    sw.stop();
    final duration = result.elapsedMs != null
        ? Duration(milliseconds: result.elapsedMs!)
        : sw.elapsed;

    final isCapped = limit != null && result.rows.length >= limit;
    String? statusMsg;
    if (result.columns.isEmpty && result.rows.isEmpty) {
      statusMsg = result.message ?? 'Command completed.';
    } else {
      final elapsedStr =
          result.elapsedMs != null ? ' in ${result.elapsedMs}ms' : '';
      statusMsg = isCapped
          ? 'Showing first $limit row(s)$elapsedStr (result capped).'
          : '${result.rows.length} row(s)$elapsedStr.';
    }

    return SqlExecutionResult(
      columns: result.columns,
      rows: result.rows,
      elapsed: duration,
      statusMessage: statusMsg,
      isTruncated: isCapped,
    );
  }

  @override
  Future<String> explainQuery(String sql) async =>
      throw UnsupportedError('EXPLAIN is not supported for generic extension drivers');

  @override
  bool get supportsExplain => false;

  @override
  Future<void> cancelQuery() async {}

  @override
  bool get supportsCancel => false;

  @override
  Future<SqlResultGridSchema> resolveTableSchema(
    String userSql,
    List<String> columns,
  ) async =>
      SqlResultGridSchema.none;

  @override
  Future<void> applyStagedMutations({
    required TableMutationPlan plan,
    Duration? timeout,
  }) async =>
      throw UnsupportedError('DML mutations are not supported for extension drivers');

  @override
  void dispose() {}
}

/// Ad-hoc SQL editor + results for extension database drivers (Block D).
class ExtensionSqlWorkspace extends material.StatefulWidget {
  const ExtensionSqlWorkspace({
    super.key,
    required this.connectionRow,
    this.selectedObject,
    this.initialSql,
  });

  final ConnectionRow connectionRow;
  final ExtensionSelectedObject? selectedObject;
  final String? initialSql;

  @override
  material.State<ExtensionSqlWorkspace> createState() =>
      _ExtensionSqlWorkspaceState();
}

class _ExtensionSqlWorkspaceState extends material.State<ExtensionSqlWorkspace> {
  late final ExtensionSqlExecutionDelegate _delegate;
  final material.GlobalKey<GenericSqlWorkspaceState> _workspaceKey =
      material.GlobalKey<GenericSqlWorkspaceState>();

  bool _restartingDriver = false;
  static const _previewRowLimit = 200;

  bool _isDriverError(String? err) {
    if (err == null) return false;
    return err.contains('PluginCrashedException') ||
        err.contains('PluginDeadlockException') ||
        err.contains('PluginProtocolTimeoutException') ||
        err.contains('TimeoutException') ||
        err.contains('SocketException') ||
        err.contains('Broken pipe') ||
        err.contains('JsonRpcStdioClient') ||
        err.contains('Connection') ||
        err.contains('is not started');
  }

  Future<void> _restartDriver() async {
    if (_restartingDriver) return;
    setState(() {
      _restartingDriver = true;
    });
    try {
      await ExtensionDriverSession.instance.restart(widget.connectionRow);
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Driver restarted successfully',
        variant: AppToastVariant.success,
      );
      setState(() {
        _restartingDriver = false;
        final ws = _workspaceKey.currentState;
        if (ws != null) {
          ws.activeSession.error = null;
        }
      });
      final ws = _workspaceKey.currentState;
      if (ws != null) {
        await ws.execute(ws.activeSession);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final ws = _workspaceKey.currentState;
        if (ws != null) {
          ws.activeSession.error = 'Driver restart failed: $e';
        }
        _restartingDriver = false;
      });
      showAppToast(
        context: context,
        message: 'Driver restart failed: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _delegate = ExtensionSqlExecutionDelegate(connectionRow: widget.connectionRow);
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      _applySelectedObject();
    });
  }

  @override
  void didUpdateWidget(covariant ExtensionSqlWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final obj = widget.selectedObject;
    final old = oldWidget.selectedObject;
    final changed = obj != null &&
        (old == null || old.database != obj.database || old.name != obj.name);
    if (changed) {
      _applySelectedObject();
    }
  }

  void _applySelectedObject() {
    final obj = widget.selectedObject;
    if (obj == null) return;
    final sql =
        'SELECT * FROM `${obj.database}`.`${obj.name}` LIMIT $_previewRowLimit';
    final ws = _workspaceKey.currentState;
    if (ws == null) return;

    if (ws.activeSession.controller.text.trim().isEmpty &&
        ws.activeSession.rows.isEmpty) {
      ws.activeSession.controller.value = material.TextEditingValue(
        text: sql,
        selection: material.TextSelection.collapsed(offset: sql.length),
      );
      ws.activeSession.title = obj.name;
      ws.invalidatePane(ws.activeSession);
      ws.setState(() {});
      unawaited(ws.execute(ws.activeSession));
    } else {
      ws.addNewTab(initialSql: sql, title: obj.name);
      unawaited(ws.execute(ws.activeSession));
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final accent = context.workbench.accent;
    return GenericSqlWorkspace(
      key: _workspaceKey,
      connectionRow: widget.connectionRow,
      delegate: _delegate,
      dialect: SqlDialect.mysql,
      sessionPrefix: 'ext',
      initialSql: widget.initialSql,
      initialTabTitle: widget.selectedObject?.name,
      supportsAutocommit: false,
      supportsStmtTimeout: false,
      effectiveDatabaseName: () => widget.connectionRow.databaseName ?? '',
      headerBadge: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Text(
            'Query · ${widget.connectionRow.name}',
          ).semiBold().small(),
        ],
      ),
      extraToolbarTrailing: (ctx, session) {
        return material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            IconButton.ghost(
              onPressed: session.running || _restartingDriver
                  ? null
                  : () => unawaited(_restartDriver()),
              icon: _restartingDriver
                  ? QueryaSpinner(
                      size: QueryaSpinnerSize.sm,
                      color: accent,
                    )
                  : material.Icon(
                      material.Icons.restart_alt_rounded,
                      size: 18,
                      color: accent,
                    ),
            ),
            const Gap(4),
            IconButton.ghost(
              onPressed: session.running
                  ? null
                  : () => unawaited(_workspaceKey.currentState?.openSqlFile()),
              icon: material.Icon(
                material.Icons.folder_open_rounded,
                size: 18,
                color: accent,
              ),
            ),
            const Gap(4),
            IconButton.ghost(
              onPressed: () =>
                  unawaited(_workspaceKey.currentState?.saveSqlFile()),
              icon: material.Icon(
                material.Icons.save_outlined,
                size: 18,
                color: accent,
              ),
            ),
          ],
        );
      },
      errorActionBuilder: (ctx, session) {
        return _isDriverError(session.error)
            ? ExtensionDriverRecoveryBanner(
                onRestart: () => unawaited(_restartDriver()),
                isRestarting: _restartingDriver,
              )
            : null;
      },
    );
  }
}
