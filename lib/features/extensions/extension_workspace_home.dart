import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_sql_workspace.dart';
import 'package:querya_desktop/features/extensions/extension_stats_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// When an extension database driver connection is selected without a table or view:
/// provides level 2 Universal UI Standard tabs: Server Stats (Overview) or SQL editor.
class ExtensionWorkspaceHome extends material.StatefulWidget {
  const ExtensionWorkspaceHome({
    super.key,
    required this.connectionRow,
    this.selectedObject,
    this.sqlTabRequestToken = 0,
    this.lastSelectedExtensionObject,
    this.onRestoreLastSelectedObject,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final ExtensionSelectedObject? selectedObject;
  final int sqlTabRequestToken;
  final bool isReadOnly;
  final ({
    String database,
    String name,
  })? lastSelectedExtensionObject;
  final VoidCallback? onRestoreLastSelectedObject;

  @override
  material.State<ExtensionWorkspaceHome> createState() =>
      _ExtensionWorkspaceHomeState();
}

class _ExtensionWorkspaceHomeState
    extends material.State<ExtensionWorkspaceHome> {
  int _tab = 0;
  int _lastAppliedSqlTabToken = 0;

  @override
  void initState() {
    super.initState();
    _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
    if (widget.selectedObject != null) {
      _tab = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ExtensionWorkspaceHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _lastAppliedSqlTabToken = widget.sqlTabRequestToken;
      _tab = widget.selectedObject != null ? 1 : 0;
      return;
    }
    final t = widget.sqlTabRequestToken;
    if (t > _lastAppliedSqlTabToken) {
      _lastAppliedSqlTabToken = t;
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_selectTab(1));
      });
    } else if (widget.selectedObject != null &&
        oldWidget.selectedObject != widget.selectedObject) {
      material.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_selectTab(1));
      });
    }
  }

  Future<void> _selectTab(int i) async {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Container(
          constraints: const material.BoxConstraints(minHeight: 44),
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: theme.colorScheme.muted.withValues(alpha: 0.6),
          ),
          child: material.Row(
            children: [
              Text(widget.connectionRow.name).semiBold().small(),
              if (widget.isReadOnly) ...[
                const Gap(6),
                material.Icon(
                  material.Icons.lock_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
              if (widget.lastSelectedExtensionObject != null &&
                  widget.onRestoreLastSelectedObject != null) ...[
                const Gap(12),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: widget.onRestoreLastSelectedObject,
                  leading: const material.Icon(
                    material.Icons.table_chart_outlined,
                    size: 14,
                  ),
                  child: Text('Return to ${widget.lastSelectedExtensionObject!.name}'),
                ),
              ],
              const Spacer(),
              QueryaTabStrip(
                labels: const ['Server', 'SQL'],
                selectedIndex: _tab,
                onSelected: (index) => unawaited(_selectTab(index)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: QueryaCrossFadeStack(
            index: _tab,
            children: [
              ExtensionStatsView(
                key: ValueKey('ext_stats_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
              ),
              ExtensionSqlWorkspace(
                key: ValueKey('ext_sql_${widget.connectionRow.id}'),
                connectionRow: widget.connectionRow,
                selectedObject: widget.selectedObject,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
