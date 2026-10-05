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

enum _BadgeVariant {
  custom,
  primaryKey,
  foreignKey,
  dataType,
  status,
  readOnly,
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
  })  : _variant = _BadgeVariant.custom,
        _status = null;

  /// Primary Key badge (distinctive type1 gold/amber badge).
  const QueryaBadge.primaryKey({
    super.key,
    this.label = 'PK',
  })  : icon = null,
        backgroundColor = null,
        foregroundColor = null,
        borderColor = null,
        isMonospace = false,
        _variant = _BadgeVariant.primaryKey,
        _status = null;

  /// Foreign Key badge (distinctive type2 blue/cyan badge).
  const QueryaBadge.foreignKey({
    super.key,
    this.label = 'FK',
  })  : icon = null,
        backgroundColor = null,
        foregroundColor = null,
        borderColor = null,
        isMonospace = false,
        _variant = _BadgeVariant.foreignKey,
        _status = null;

  /// SQL / NoSQL data type badge (monospace label with subtle tint).
  const QueryaBadge.dataType(
    this.label, {
    super.key,
  })  : icon = null,
        backgroundColor = null,
        foregroundColor = null,
        borderColor = null,
        isMonospace = true,
        _variant = _BadgeVariant.dataType,
        _status = null;

  /// Operational or connection status badge.
  const QueryaBadge.status(
    this.label, {
    super.key,
    required QueryaBadgeStatus status,
  })  : icon = null,
        backgroundColor = null,
        foregroundColor = null,
        borderColor = null,
        isMonospace = false,
        _variant = _BadgeVariant.status,
        _status = status;

  /// Read-only indicator badge.
  const QueryaBadge.readOnly({
    super.key,
    this.label = 'READ ONLY',
  })  : icon = null,
        backgroundColor = null,
        foregroundColor = null,
        borderColor = null,
        isMonospace = false,
        _variant = _BadgeVariant.readOnly,
        _status = null;

  final String label;
  final material.Widget? icon;
  final material.Color? backgroundColor;
  final material.Color? foregroundColor;
  final material.Color? borderColor;
  final bool isMonospace;

  final _BadgeVariant _variant;
  final QueryaBadgeStatus? _status;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final palette = context.semanticPalette;

    material.Color fg;
    material.Color bg;
    material.Color border;
    material.Widget? effectiveIcon = icon;
    String effectiveLabel = label;

    switch (_variant) {
      case _BadgeVariant.primaryKey:
        fg = palette.type1;
        bg = fg.withValues(alpha: 0.12);
        border = fg.withValues(alpha: 0.3);
        effectiveIcon = const material.Icon(material.Icons.vpn_key_rounded);
        break;
      case _BadgeVariant.foreignKey:
        fg = palette.type2;
        bg = fg.withValues(alpha: 0.12);
        border = fg.withValues(alpha: 0.3);
        effectiveIcon = const material.Icon(material.Icons.link_rounded);
        break;
      case _BadgeVariant.dataType:
        fg = workbench?.mutedForeground ?? cs.mutedForeground;
        bg = cs.muted.withValues(alpha: 0.3);
        border = cs.border.withValues(alpha: 0.5);
        effectiveLabel = label.toUpperCase();
        break;
      case _BadgeVariant.status:
        material.IconData? statusIcon;
        switch (_status ?? QueryaBadgeStatus.neutral) {
          case QueryaBadgeStatus.success:
            fg = workbench?.success ?? palette.success;
            statusIcon = material.Icons.check_circle_outline_rounded;
            break;
          case QueryaBadgeStatus.warning:
            fg = workbench?.warning ?? const material.Color(0xFFE88C30);
            statusIcon = material.Icons.warning_amber_rounded;
            break;
          case QueryaBadgeStatus.error:
            fg = workbench?.destructive ?? palette.destructive;
            statusIcon = material.Icons.error_outline_rounded;
            break;
          case QueryaBadgeStatus.info:
            fg = workbench?.accent ?? cs.primary;
            statusIcon = material.Icons.info_outline_rounded;
            break;
          case QueryaBadgeStatus.neutral:
            fg = workbench?.mutedForeground ?? cs.mutedForeground;
            statusIcon = null;
            break;
        }
        bg = fg.withValues(alpha: 0.12);
        border = fg.withValues(alpha: 0.3);
        if (statusIcon != null) {
          effectiveIcon = material.Icon(statusIcon);
        }
        break;
      case _BadgeVariant.readOnly:
        fg = workbench?.mutedForeground ?? cs.mutedForeground;
        bg = cs.muted.withValues(alpha: 0.4);
        border = cs.border.withValues(alpha: 0.6);
        effectiveIcon = const material.Icon(material.Icons.lock_outline_rounded);
        break;
      case _BadgeVariant.custom:
        fg = foregroundColor ?? cs.foreground;
        bg = backgroundColor ?? cs.muted.withValues(alpha: 0.35);
        border = borderColor ?? fg.withValues(alpha: 0.2);
        break;
    }

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
          if (effectiveIcon != null) ...[
            material.IconTheme(
              data: material.IconThemeData(
                size: 11,
                color: fg,
              ),
              child: effectiveIcon,
            ),
            const Gap(4),
          ],
          material.Text(
            effectiveLabel,
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
