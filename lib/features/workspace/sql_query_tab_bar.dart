import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Lightweight query tab strip rendered above the SQL editor workspace.
class SqlQueryTabBar extends material.StatelessWidget {
  const SqlQueryTabBar({
    super.key,
    required this.sessions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    this.onClose,
    this.actions,
    this.trailing,
  });

  final List<SqlQueryTabSession> sessions;
  final int selectedIndex;
  final material.ValueChanged<int> onSelect;
  final material.VoidCallback onAdd;
  final material.ValueChanged<int>? onClose;

  /// The run controls of the active query tab, right of the tabs. They get
  /// what the tabs leave ([minTabsWidth] stays with the tabs), so the strip is
  /// the only control row above the editor (#1558).
  final material.Widget? actions;

  /// Shown at the right end of the strip (the schema diagram button).
  final material.Widget? trailing;

  /// Width kept for the tabs when the actions are wide: at least this much,
  /// and enough for every tab and the add button as tabs are added, up to
  /// [maxTabsShare] of the strip, so a new tab and the add button are not pushed
  /// out of view by the controls.
  static const double minTabsWidth = 180;
  static const double maxTabsShare = 0.6;

  @override
  material.Widget build(material.BuildContext context) {
    // The same surface as the rest of the SQL pane: workbench surface, hairline.
    return material.Container(
      height: 40,
      padding: const material.EdgeInsets.symmetric(horizontal: 8),
      decoration: SqlEditorChrome.sqlToolbarDecoration(context),
      child: material.LayoutBuilder(
        builder: (context, constraints) {
          final tabsWidth = math.min(
            math.max(
              minTabsWidth,
              QueryaTabStrip.naturalWidth(
                [for (final s in sessions) s.title],
                closable: sessions.length > 1,
              ),
            ),
            constraints.maxWidth * maxTabsShare,
          );
          final tail = material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              // Flexible: the actions are measured against what is left after
              // the trailing button, and size their labels to it.
              if (actions != null) material.Flexible(child: actions!),
              if (actions != null && trailing != null)
                const material.SizedBox(width: 8),
              if (trailing != null) trailing!,
            ],
          );
          return material.Row(
            children: [
              material.Expanded(
                child: QueryaTabStrip(
                  labels: sessions.map((s) => s.title).toList(),
                  selectedIndex: selectedIndex,
                  onSelected: onSelect,
                  onClose: onClose,
                  onAdd: onAdd,
                  canClose: sessions.length > 1 ? (_) => true : (_) => false,
                ),
              ),
              if (actions != null || trailing != null) ...[
                const material.SizedBox(width: 8),
                material.ConstrainedBox(
                  constraints: material.BoxConstraints(
                    maxWidth: (constraints.maxWidth - tabsWidth - 8)
                        .clamp(0.0, double.infinity),
                  ),
                  child: tail,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Prompts confirmation when attempting to close a query tab that has uncommitted
/// staged database modifications.
Future<bool?> showUnsavedTabChangesDialog({
  required material.BuildContext context,
  required String tabTitle,
  String? message,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      return QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 420),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              Text('Unsaved Changes in "$tabTitle"').semiBold().large(),
              const Gap(8),
              Text(
                message ??
                    'This query tab contains staged database changes that have not been applied yet. Closing the tab will discard these changes.',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    QueryaButton.ghost(
                      label: 'Cancel',
                      onPressed: () => material.Navigator.of(ctx).pop(false),
                      size: QueryaControlSize.md,
                    ),
                    QueryaButton.destructive(
                      label: 'Discard & Close',
                      onPressed: () => material.Navigator.of(ctx).pop(true),
                      size: QueryaControlSize.md,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
