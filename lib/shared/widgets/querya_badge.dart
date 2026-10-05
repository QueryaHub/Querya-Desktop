import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// Semantic status variant for [QueryaBadge.status].
enum QueryaBadgeStatus {
  success,
  warning,
  error,
  info,
  neutral,
}

/// Standard semantic badge widget for database types, constraints, and status indicators.
class QueryaBadge extends material.StatelessWidget {
  const QueryaBadge({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.isMonospace = false,
  });

  /// Primary Key badge (distinctive type1 gold/amber badge).
  const factory QueryaBadge.primaryKey({
    material.Key? key,
    String label,
  }) = _QueryaPrimaryKeyBadge;

  /// Foreign Key badge (distinctive type2 blue/cyan badge).
  const factory QueryaBadge.foreignKey({
    material.Key? key,
    String label,
  }) = _QueryaForeignKeyBadge;

  /// SQL / NoSQL data type badge (monospace label with subtle tint).
  const factory QueryaBadge.dataType(
    String type, {
    material.Key? key,
  }) = _QueryaDataTypeBadge;

  /// Operational or connection status badge.
  const factory QueryaBadge.status(
    String label, {
    material.Key? key,
    required QueryaBadgeStatus status,
  }) = _QueryaStatusBadge;

  /// Read-only indicator badge.
  const factory QueryaBadge.readOnly({
    material.Key? key,
    String label,
  }) = _QueryaReadOnlyBadge;

  final String label;
  final material.Widget? icon;
  final material.Color? backgroundColor;
  final material.Color? foregroundColor;
  final material.Color? borderColor;
  final bool isMonospace;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = foregroundColor ?? cs.foreground;
    final bg = backgroundColor ?? cs.muted.withValues(alpha: 0.35);
    final border = borderColor ?? fg.withValues(alpha: 0.2);

    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: material.BoxDecoration(
        color: bg,
        borderRadius: material.BorderRadius.circular(4),
        border: material.Border.all(color: border, width: 1),
      ),
      child: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            material.IconTheme(
              data: material.IconThemeData(
                size: 11,
                color: fg,
              ),
              child: icon!,
            ),
            const Gap(4),
          ],
          material.Text(
            label,
            style: material.TextStyle(
              fontSize: 10,
              fontWeight: material.FontWeight.w600,
              fontFamily: isMonospace ? 'monospace' : null,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueryaPrimaryKeyBadge extends QueryaBadge {
  const _QueryaPrimaryKeyBadge({
    super.key,
    super.label = 'PK',
  });

  @override
  material.Widget build(material.BuildContext context) {
    final palette = context.semanticPalette;
    final fg = palette.type1;
    final bg = fg.withValues(alpha: 0.12);

    return QueryaBadge(
      label: label,
      icon: const material.Icon(material.Icons.vpn_key_rounded),
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.3),
    );
  }
}

class _QueryaForeignKeyBadge extends QueryaBadge {
  const _QueryaForeignKeyBadge({
    super.key,
    super.label = 'FK',
  });

  @override
  material.Widget build(material.BuildContext context) {
    final palette = context.semanticPalette;
    final fg = palette.type2;
    final bg = fg.withValues(alpha: 0.12);

    return QueryaBadge(
      label: label,
      icon: const material.Icon(material.Icons.link_rounded),
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.3),
    );
  }
}

class _QueryaDataTypeBadge extends QueryaBadge {
  const _QueryaDataTypeBadge(
    super.label, {
    super.key,
  }) : super(isMonospace: true);

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final fg = workbench?.mutedForeground ?? cs.mutedForeground;
    final bg = cs.muted.withValues(alpha: 0.3);

    return QueryaBadge(
      label: label.toUpperCase(),
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: cs.border.withValues(alpha: 0.5),
      isMonospace: true,
    );
  }
}

class _QueryaStatusBadge extends QueryaBadge {
  const _QueryaStatusBadge(
    super.label, {
    super.key,
    required this.status,
  });

  final QueryaBadgeStatus status;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final palette = context.semanticPalette;

    material.Color fg;
    material.IconData? iconData;

    switch (status) {
      case QueryaBadgeStatus.success:
        fg = workbench?.success ?? palette.success;
        iconData = material.Icons.check_circle_outline_rounded;
        break;
      case QueryaBadgeStatus.warning:
        fg = workbench?.warning ?? material.const Color(0xFFE88C30);
        iconData = material.Icons.warning_amber_rounded;
        break;
      case QueryaBadgeStatus.error:
        fg = workbench?.destructive ?? palette.destructive;
        iconData = material.Icons.error_outline_rounded;
        break;
      case QueryaBadgeStatus.info:
        fg = workbench?.accent ?? cs.primary;
        iconData = material.Icons.info_outline_rounded;
        break;
      case QueryaBadgeStatus.neutral:
        fg = workbench?.mutedForeground ?? cs.mutedForeground;
        iconData = null;
        break;
    }

    final bg = fg.withValues(alpha: 0.12);

    return QueryaBadge(
      label: label,
      icon: iconData != null ? material.Icon(iconData) : null,
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: fg.withValues(alpha: 0.3),
    );
  }
}

class _QueryaReadOnlyBadge extends QueryaBadge {
  const _QueryaReadOnlyBadge({
    super.key,
    super.label = 'READ ONLY',
  });

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final fg = workbench?.mutedForeground ?? cs.mutedForeground;
    final bg = cs.muted.withValues(alpha: 0.4);

    return QueryaBadge(
      label: label,
      icon: const material.Icon(material.Icons.lock_outline_rounded),
      backgroundColor: bg,
      foregroundColor: fg,
      borderColor: cs.border.withValues(alpha: 0.6),
    );
  }
}
