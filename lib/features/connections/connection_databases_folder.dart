import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/core/ui/querya_tree_indent_guide.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Collapsible **Databases (N)** folder chrome for network drivers
/// (PostgreSQL / MySQL / MongoDB / Redis).
///
/// Defaults to expanded; uses [QueryaMotion.treeExpand] for the chevron and
/// [QueryaAnimatedExpand] for the child list.
class ConnectionDatabasesFolder extends material.StatefulWidget {
  const ConnectionDatabasesFolder({
    super.key,
    required this.connection,
    required this.databaseCount,
    required this.child,
    this.onRefresh,
    this.onOpenSql,
    this.initiallyExpanded = true,
  });

  final ConnectionRow connection;
  final int databaseCount;
  final material.Widget child;
  final material.VoidCallback? onRefresh;

  /// Optional "Open in SQL" context action (PG / MySQL).
  final material.VoidCallback? onOpenSql;

  final bool initiallyExpanded;

  @override
  material.State<ConnectionDatabasesFolder> createState() =>
      _ConnectionDatabasesFolderState();
}

class _ConnectionDatabasesFolderState
    extends material.State<ConnectionDatabasesFolder> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant ConnectionDatabasesFolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded &&
        oldWidget.databaseCount == 0 &&
        widget.databaseCount > 0) {
      _expanded = widget.initiallyExpanded;
    }
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final label = 'Databases (${widget.databaseCount})';

    final row = material.CallbackShortcuts(
      bindings: {
        if (!_expanded)
          const material.SingleActivator(LogicalKeyboardKey.arrowRight): _toggle,
        if (_expanded)
          const material.SingleActivator(LogicalKeyboardKey.arrowLeft): _toggle,
      },
      child: material.AnimatedContainer(
        duration: context.motionDuration(QueryaMotion.fast),
        curve: context.motionCurve(QueryaMotion.standardCurve),
        decoration: material.BoxDecoration(
          color: material.Colors.transparent,
          borderRadius: material.BorderRadius.circular(4),
        ),
        child: material.Material(
          color: material.Colors.transparent,
          child: material.InkWell(
            onTap: _toggle,
            borderRadius: material.BorderRadius.circular(4),
            hoverColor: primary.withValues(alpha: 0.07),
            focusColor: primary.withValues(alpha: 0.14),
            splashColor: primary.withValues(alpha: 0.10),
            highlightColor: primary.withValues(alpha: 0.05),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              child: material.Row(
                children: [
                  material.AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: context.motionDuration(QueryaMotion.treeExpand),
                    curve: context.motionCurve(QueryaMotion.treeExpandCurve),
                    child: material.Icon(
                      QueryaIcons.expandClosed,
                      size: QueryaIconSizes.treeExpand,
                      color: muted,
                    ),
                  ),
                  const Gap(4),
                  material.Icon(
                    QueryaIcons.databasesFolder,
                    size: QueryaIconSizes.treeConnection,
                    color: primary.withValues(alpha: 0.7),
                  ),
                  const Gap(6),
                  material.Expanded(
                    child: material.Text(
                      label,
                      overflow: material.TextOverflow.ellipsis,
                      maxLines: 1,
                      style: material.TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final menu = ContextMenu(
      items: [
        if (widget.onRefresh != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.refresh_rounded,
              size: 18,
              color: muted,
            ),
            onPressed: (_) => widget.onRefresh!(),
            child: const Text('Refresh'),
          ),
        MenuButton(
          leading: material.Icon(
            material.Icons.copy_rounded,
            size: 18,
            color: muted,
          ),
          onPressed: (_) {
            Clipboard.setData(ClipboardData(text: label));
          },
          child: const Text('Copy name'),
        ),
        if (widget.onOpenSql != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: muted,
            ),
            onPressed: (_) => widget.onOpenSql!(),
            child: const Text('Open in SQL'),
          ),
      ],
      child: row,
    );

    return QueryaTreeIndentGuide(
      depth: 1,
      step: QueryaTreeTokens.underConnection,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Semantics(
            button: true,
            expanded: _expanded,
            label: label,
            child: menu,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            estimatedChildCount: widget.databaseCount,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
