import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Choices for the session options dropdown.
sealed class SqlWorkspaceSessionChoice {
  const SqlWorkspaceSessionChoice();
}

class ToggleAutocommitChoice extends SqlWorkspaceSessionChoice {
  const ToggleAutocommitChoice();
}

class SetStatementTimeoutChoice extends SqlWorkspaceSessionChoice {
  const SetStatementTimeoutChoice(this.seconds);
  final int? seconds;
}

class BeginTransactionChoice extends SqlWorkspaceSessionChoice {
  const BeginTransactionChoice();
}

class OpenPreferencesChoice extends SqlWorkspaceSessionChoice {
  const OpenPreferencesChoice();
}

/// Standalone single-row toolbar for SQL workspaces.
///
/// Encapsulates statement and script execution controls, explain/cancel actions,
/// history, format, file operations, active database/transaction indicators,
/// and session configuration menu.
class SqlWorkspaceToolbar extends StatelessWidget {
  const SqlWorkspaceToolbar({
    super.key,
    required this.session,
    required this.delegate,
    required this.effectiveDatabase,
    required this.autocommit,
    required this.supportsAutocommit,
    required this.supportsStmtTimeout,
    required this.txOpen,
    required this.queryTimeoutSeconds,
    this.headerBadge,
    this.extraTrailing,
    required this.historyEnabled,
    required this.onExecute,
    required this.onExplain,
    required this.onCancel,
    required this.onOpenHistory,
    required this.onOpenFile,
    required this.onSaveFile,
    required this.onRunTxCommand,
    required this.onToggleAutocommit,
    required this.onTimeoutChanged,
  });

  final SqlQueryTabSession session;
  final SqlExecutionDelegate delegate;
  final String effectiveDatabase;
  final bool autocommit;
  final bool supportsAutocommit;
  final bool supportsStmtTimeout;
  final bool? txOpen;
  final int? queryTimeoutSeconds;
  final material.Widget? headerBadge;
  final material.Widget? extraTrailing;
  final bool historyEnabled;

  final void Function(bool statementAtCursor) onExecute;
  final VoidCallback onExplain;
  final VoidCallback onCancel;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenFile;
  final VoidCallback onSaveFile;
  final void Function(String command) onRunTxCommand;
  final VoidCallback onToggleAutocommit;
  final void Function(int? seconds) onTimeoutChanged;

  /// Below this width only the run button keeps its label; the rest are
  /// icons. Below [iconOnlyWidth] the run button is an icon too.
  static const double labelsWidth = 900;
  static const double iconOnlyWidth = 620;
  static String get _modLabel => Platform.isMacOS ? '⌘' : 'Ctrl+';

  List<QueryaActionMenuItem<SqlWorkspaceSessionChoice>> _sessionMenuItems() => [
        if (supportsAutocommit)
          QueryaActionMenuItem(
            value: const ToggleAutocommitChoice(),
            label: autocommit ? 'Autocommit: on' : 'Autocommit: off',
          ),
        if (supportsStmtTimeout)
          for (final option in kSqlStatementTimeoutMenuItems)
            QueryaActionMenuItem(
              value: SetStatementTimeoutChoice(option.value),
              label: 'Timeout: ${option.label}'
                  '${option.value == queryTimeoutSeconds ? '  ✓' : ''}',
            ),
        if (delegate.supportsTransactions && txOpen != true)
          const QueryaActionMenuItem(
            value: BeginTransactionChoice(),
            label: 'Begin transaction',
          ),
        const QueryaActionMenuItem(
          value: OpenPreferencesChoice(),
          label: 'Preferences…',
        ),
      ];

  void _onSessionChoice(
    material.BuildContext context,
    SqlWorkspaceSessionChoice choice,
  ) {
    switch (choice) {
      case ToggleAutocommitChoice():
        onToggleAutocommit();
      case SetStatementTimeoutChoice(:final seconds):
        onTimeoutChanged(seconds);
      case BeginTransactionChoice():
        onRunTxCommand('BEGIN');
      case OpenPreferencesChoice():
        showPreferencesDialog(context);
    }
  }

  /// What is not the default: an open transaction or manual commit. Auto-commit
  /// is the default and is named by the Session menu, so it has no badge of its
  /// own next to it (#1558).
  material.Widget? _txBadge() {
    if (txOpen == true) {
      return const QueryaBadge.status(
        'Transaction open',
        status: QueryaBadgeStatus.warning,
      );
    }
    if (!autocommit) {
      return const QueryaBadge.status(
        'Manual commit',
        status: QueryaBadgeStatus.info,
      );
    }
    return null;
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.LayoutBuilder(
      builder: (context, constraints) {
        // Controls give up their labels as the row narrows, the run button
        // last, so the row stays on one line without hiding what it does.
        final compact = constraints.maxWidth < labelsWidth;
        final runCompact = constraints.maxWidth < iconOnlyWidth;
        // One size for the whole row: the run split button, the buttons, the
        // icon buttons and the session menu are all `md` (#1439).
        return QueryaControlScope(
          size: QueryaControlSize.md,
          child: material.SingleChildScrollView(
          scrollDirection: material.Axis.horizontal,
          child: material.Row(
            children: [
              if (headerBadge != null) ...[
                headerBadge!,
                const material.SizedBox(width: 12),
              ],
              QueryaSplitButton<bool>(
                mainKey: const material.ValueKey('run_script'),
                menuKey: const material.ValueKey('run_menu'),
                label: 'Execute (F5)',
                icon: material.Icons.play_arrow_rounded,
                compact: runCompact,
                loading: session.running,
                onPressed: () => onExecute(false),
                menuTooltip: 'Run options',
                items: [
                  QueryaActionMenuItem(
                    value: true,
                    label: 'Run statement (${_modLabel}Enter)',
                    icon: material.Icons.short_text_rounded,
                  ),
                  const QueryaActionMenuItem(
                    value: false,
                    label: 'Run script (F5)',
                    icon: material.Icons.list_alt_rounded,
                  ),
                ],
                onSelected: (atCursor) {
                  if (!session.running) {
                    onExecute(atCursor);
                  }
                },
              ),
              if (delegate.supportsExplain) ...[
                const material.SizedBox(width: 8),
                // A magnifier over lines: the plan. The diagram keeps the tree.
                QueryaButton.ghost(
                  key: const material.ValueKey('explain_query'),
                  label: 'Explain',
                  icon: material.Icons.manage_search_rounded,
                  compact: compact,
                  tooltip: 'Show the query plan',
                  onPressed: session.running ? null : onExplain,
                ),
              ],
              if (session.running && delegate.supportsCancel) ...[
                const material.SizedBox(width: 8),
                QueryaButton.secondary(
                  key: const material.ValueKey('cancel_query'),
                  label: 'Cancel',
                  icon: material.Icons.stop_rounded,
                  compact: compact,
                  tone: QueryaButtonTone.destructive,
                  tooltip: 'Interrupt the running query',
                  onPressed: onCancel,
                ),
              ],
              const material.SizedBox(width: 16),
              QueryaIconButton(
                key: const material.ValueKey('history_button'),
                icon: const material.Icon(material.Icons.history_rounded),
                tooltip: 'History (${_modLabel}H)',
                onPressed: historyEnabled ? onOpenHistory : null,
              ),
              QueryaIconButton(
                key: const material.ValueKey('format_button'),
                icon: const material.Icon(material.Icons.auto_fix_high_rounded),
                tooltip: 'Format (Shift+Alt+F)',
                onPressed: session.running ? null : () => session.formatSql(),
              ),
              QueryaIconButton(
                key: const material.ValueKey('open_sql_button'),
                icon: const material.Icon(material.Icons.folder_open_outlined),
                tooltip: 'Open .sql file',
                onPressed: onOpenFile,
              ),
              QueryaIconButton(
                key: const material.ValueKey('save_sql_button'),
                icon: const material.Icon(material.Icons.save_outlined),
                tooltip: 'Save .sql file',
                onPressed: onSaveFile,
              ),
              const material.SizedBox(width: 16),
              if (effectiveDatabase.isNotEmpty) ...[
                QueryaBadge.status(
                  effectiveDatabase,
                  status: QueryaBadgeStatus.neutral,
                ),
                const material.SizedBox(width: 8),
              ],
              if (delegate.supportsTransactions) ...[
                if (_txBadge() case final badge?) badge,
                if (txOpen == true) ...[
                  const material.SizedBox(width: 8),
                  QueryaButton.secondary(
                    label: 'Commit',
                    onPressed:
                        session.running ? null : () => onRunTxCommand('COMMIT'),
                  ),
                  const material.SizedBox(width: 4),
                  QueryaButton.secondary(
                    label: 'Rollback',
                    onPressed: session.running
                        ? null
                        : () => onRunTxCommand('ROLLBACK'),
                  ),
                ],
                const material.SizedBox(width: 8),
              ],
              QueryaMenuButton<SqlWorkspaceSessionChoice>(
                key: const material.ValueKey('session_menu'),
                variant: QueryaButtonVariant.ghost,
                items: _sessionMenuItems(),
                onSelected: (choice) => _onSessionChoice(context, choice),
                enabled: !session.running,
                icon: material.Icons.tune_rounded,
                tooltip: autocommit
                    ? 'Session: auto-commit'
                    : 'Session: manual commit',
                label: compact
                    ? null
                    : (autocommit ? 'Session · auto-commit' : 'Session · manual'),
              ),
              if (extraTrailing != null) ...[
                const material.SizedBox(width: 8),
                extraTrailing!,
              ],
            ],
          ),
          ),
        );
      },
    );
  }
}
