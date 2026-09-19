import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens SQL workspace; optional tree fields seed the editor.
typedef QueryaOpenSqlWorkspace = void Function(
  ConnectionRow connection, {
  String? database,
  String? schema,
  String? name,
  PostgresObjectKind? kind,
});

/// Ellipsis label; tooltip when the name is long enough to likely truncate.
class _QueryaConnectionTreeRowLabel extends material.StatelessWidget {
  const _QueryaConnectionTreeRowLabel({
    required this.label,
    required this.textStyle,
  });

  final String label;
  final material.TextStyle textStyle;

  static const int _tooltipMinLength = 28;

  @override
  material.Widget build(material.BuildContext context) {
    final text = material.Text(
      label,
      overflow: material.TextOverflow.ellipsis,
      maxLines: 1,
      style: textStyle,
    );
    if (label.length < _tooltipMinLength) return text;
    return material.Tooltip(
      message: label,
      waitDuration: kQueryaTooltipWait,
      child: text,
    );
  }
}

/// Shared tree row: consistent ink hover, optional context menu, tooltips when truncated.
class QueryaConnectionTreeRow extends material.StatelessWidget {
  const QueryaConnectionTreeRow({
    super.key,
    required this.label,
    this.isSelected = false,
    this.leading,
    this.icon,
    this.iconWidget,
    this.iconSize = QueryaIconSizes.treeGroup,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.expanded,
    this.verticalPadding = 3,
    required this.textStyle,
    this.connection,
    this.onContextRefresh,
    this.onOpenSqlWorkspace,
    this.openSqlDatabase,
    this.openSqlSchema,
    this.openSqlName,
    this.openSqlKind,
    this.onContextDelete,
    this.contextDeleteLabel,
    this.isPinned = false,
    this.onTogglePin,
  });

  final String label;
  final bool isSelected;
  final material.Widget? leading;
  final material.IconData? icon;
  /// When set, drawn instead of [icon] (e.g. inline loading spinner).
  final material.Widget? iconWidget;
  final double iconSize;
  final material.Color? iconColor;
  final material.Widget? trailing;
  final void Function()? onTap;

  /// When non-null, row is an expand control ([Semantics.button] + expanded).
  final bool? expanded;
  final double verticalPadding;
  final material.TextStyle textStyle;
  final ConnectionRow? connection;
  final VoidCallback? onContextRefresh;
  final QueryaOpenSqlWorkspace? onOpenSqlWorkspace;
  final String? openSqlDatabase;
  final String? openSqlSchema;
  final String? openSqlName;
  final PostgresObjectKind? openSqlKind;
  final VoidCallback? onContextDelete;
  final String? contextDeleteLabel;
  final bool isPinned;
  final VoidCallback? onTogglePin;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final row = material.CallbackShortcuts(
      bindings: {
        if (expanded == false && onTap != null)
          const material.SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              onTap!(),
        if (expanded == true && onTap != null)
          const material.SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              onTap!(),
      },
      child: _selectionChrome(
        context: context,
        primary: primary,
        child: material.Material(
          color: material.Colors.transparent,
          child: material.InkWell(
            onTap: onTap,
            canRequestFocus: onTap != null,
            borderRadius: material.BorderRadius.circular(4),
            hoverColor: primary.withValues(alpha: 0.07),
            focusColor: primary.withValues(alpha: 0.14),
            splashColor: primary.withValues(alpha: 0.10),
            highlightColor: primary.withValues(alpha: 0.05),
            mouseCursor: onTap != null
                ? material.SystemMouseCursors.click
                : material.SystemMouseCursors.basic,
            child: material.Padding(
              padding: material.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: verticalPadding,
              ),
              child: material.Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const Gap(4),
                  ],
                  if (iconWidget != null) ...[
                    iconWidget!,
                    const Gap(6),
                  ] else if (icon != null) ...[
                    material.Icon(
                      icon,
                      size: iconSize,
                      color: isSelected ? primary : (iconColor ?? muted),
                    ),
                    const Gap(6),
                  ],
                  if (isPinned) ...[
                    material.Icon(
                      material.Icons.star_rounded,
                      size: 13,
                      color: material.Colors.amber.shade600,
                    ),
                    const Gap(4),
                  ],
                  material.Expanded(
                    child: _QueryaConnectionTreeRowLabel(
                      label: label,
                      textStyle: isSelected
                          ? textStyle.copyWith(
                              fontWeight: material.FontWeight.w600,
                              color: theme.colorScheme.foreground,
                            )
                          : textStyle,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final wantsMenu = connection != null ||
        onContextRefresh != null ||
        onContextDelete != null ||
        onOpenSqlWorkspace != null ||
        onTogglePin != null;
    if (!wantsMenu) {
      return expanded == null
          ? row
          : material.Semantics(
              button: true,
              expanded: expanded,
              child: row,
            );
    }
    final menu = ContextMenu(
      items: [
        if (openSqlName != null) ...[
          if (onTogglePin != null) ...[
            MenuButton(
              leading: material.Icon(
                isPinned
                    ? material.Icons.star_rounded
                    : material.Icons.star_border_rounded,
                size: 18,
                color: isPinned
                    ? material.Colors.amber.shade600
                    : theme.colorScheme.mutedForeground,
              ),
              onPressed: (_) => onTogglePin!(),
              child: Text(isPinned ? 'Unpin from top' : 'Pin to top ⭐'),
            ),
            const MenuDivider(),
          ],
          MenuButton(
            leading: material.Icon(
              material.Icons.table_rows_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            onPressed: (_) {
              final qualified = openSqlSchema != null && openSqlSchema!.isNotEmpty
                  ? '"$openSqlSchema"."$openSqlName"'
                  : '"$openSqlName"';
              Clipboard.setData(
                ClipboardData(text: 'SELECT * FROM $qualified LIMIT 100;'),
              );
              if (onOpenSqlWorkspace != null && connection != null) {
                onOpenSqlWorkspace!(
                  connection!,
                  database: openSqlDatabase,
                  schema: openSqlSchema,
                  name: openSqlName,
                  kind: openSqlKind,
                );
              }
            },
            child: const Text('Select TOP 100'),
          ),
          MenuButton(
            leading: material.Icon(
              material.Icons.code_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) {
              final qualified = openSqlSchema != null && openSqlSchema!.isNotEmpty
                  ? '"$openSqlSchema"."$openSqlName"'
                  : '"$openSqlName"';
              Clipboard.setData(ClipboardData(text: 'SELECT * FROM $qualified;'));
            },
            child: const Text('Copy SELECT statement'),
          ),
          const MenuDivider(),
        ],
        if (onContextRefresh != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.refresh_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onContextRefresh!(),
            child: const Text('Refresh'),
          ),
        MenuButton(
          leading: material.Icon(
            material.Icons.copy_rounded,
            size: 18,
            color: theme.colorScheme.mutedForeground,
          ),
          onPressed: (_) {
            Clipboard.setData(ClipboardData(text: label));
          },
          child: const Text('Copy name'),
        ),
        if (onOpenSqlWorkspace != null &&
            openSqlName == null &&
            connection != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onOpenSqlWorkspace!(
              connection!,
              database: openSqlDatabase,
              schema: openSqlSchema,
              name: openSqlName,
              kind: openSqlKind,
            ),
            child: const Text('Open in SQL'),
          ),
        if (onContextDelete != null) ...[
          const MenuDivider(),
          MenuButton(
            leading: material.Icon(
              material.Icons.delete_outline_rounded,
              size: 18,
              color: theme.colorScheme.destructive,
            ),
            onPressed: (_) => onContextDelete!(),
            child: Text(contextDeleteLabel ?? 'Delete'),
          ),
        ],
      ],
      child: row,
    );
    if (expanded == null) return menu;
    return material.Semantics(
      button: true,
      expanded: expanded,
      child: menu,
    );
  }

  /// Selection fill: [AnimatedContainer] on Full motion, instant [DecoratedBox]
  /// when Motion Off / OS reduce-motion (no leftover animation controllers).
  material.Widget _selectionChrome({
    required material.BuildContext context,
    required material.Color primary,
    required material.Widget child,
  }) {
    final decoration = material.BoxDecoration(
      color: isSelected
          ? primary.withValues(alpha: 0.12)
          : material.Colors.transparent,
      borderRadius: material.BorderRadius.circular(4),
      border: isSelected
          ? material.Border.all(
              color: primary.withValues(alpha: 0.35),
              width: 1,
            )
          : null,
    );
    final duration = context.motionDuration(QueryaMotion.fast);
    if (duration == Duration.zero) {
      return material.DecoratedBox(decoration: decoration, child: child);
    }
    return material.AnimatedContainer(
      duration: duration,
      curve: context.motionCurve(QueryaMotion.standardCurve),
      decoration: decoration,
      child: child,
    );
  }
}

