import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';

/// Legacy names of the control sizes: [dense] is [QueryaControlSize.sm] and
/// [standard] is [QueryaControlSize.md]. New code passes a [QueryaControlSize].
enum QueryaIconButtonDensity {
  /// [QueryaControlSize.sm]: dense trees, tab bars, data grid calc bars.
  dense(QueryaControlSize.sm),

  /// [QueryaControlSize.md]: top toolbars and header chrome.
  standard(QueryaControlSize.md);

  const QueryaIconButtonDensity(this.controlSize);

  final QueryaControlSize controlSize;

  double get boxSize => controlSize.height;
  double get iconSize => controlSize.iconSize;
}

/// Standard icon button with density presets, hover/active states, and built-in tooltip.
class QueryaIconButton extends material.StatefulWidget {
  const QueryaIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.density,
    this.size,
    this.isActive = false,
    this.isDestructive = false,
    this.color,
    this.activeColor,
    this.borderRadius,
  });

  /// The icon widget or Icon to render.
  final material.Widget icon;

  /// Optional tooltip message shown on hover using [kQueryaTooltipWait].
  final String? tooltip;

  /// Callback when pressed. If null, the button is disabled.
  final material.VoidCallback? onPressed;

  /// Legacy size name; [size] wins when both are set.
  final QueryaIconButtonDensity? density;

  /// Control size. Without one the button takes the nearest
  /// [QueryaControlScope], then [QueryaControlSize.md].
  final QueryaControlSize? size;

  /// Whether the button is currently in an active/toggled state.
  final bool isActive;

  /// Whether clicking triggers a destructive action (tinted red on hover).
  final bool isDestructive;

  /// Custom icon color in normal state.
  final material.Color? color;

  /// Custom icon color in active state.
  final material.Color? activeColor;

  /// Custom border radius. Defaults to 6px.
  final material.BorderRadius? borderRadius;

  @override
  material.State<QueryaIconButton> createState() => _QueryaIconButtonState();
}

class _QueryaIconButtonState extends material.State<QueryaIconButton> {
  /// Whether the button has keyboard focus (#1370): drawn as a 2px ring.
  bool _focused = false;

  @override
  material.Widget build(material.BuildContext context) {
    final icon = widget.icon;
    final tooltip = widget.tooltip;
    final onPressed = widget.onPressed;
    final controlSize = widget.size ??
        widget.density?.controlSize ??
        QueryaControlSize.of(context);
    final boxSize = controlSize.scaledHeight(context);
    final iconSize = controlSize.scaledIconSize(context);
    final isActive = widget.isActive;
    final isDestructive = widget.isDestructive;
    final color = widget.color;
    final activeColor = widget.activeColor;
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final radius = widget.borderRadius ??
        material.BorderRadius.circular(controlSize.scaledRadius(context));

    final isEnabled = onPressed != null;

    final destructiveColor = workbench?.destructive ?? cs.destructive;
    final accentColor = workbench?.accent ?? cs.primary;
    final mutedColor = workbench?.mutedForeground ?? cs.mutedForeground;

    // Normal icon color
    final normalColor = color ??
        (isDestructive
            ? destructiveColor
            : (isEnabled ? cs.foreground : cs.mutedForeground.withValues(alpha: 0.5)));

    // Effective icon color
    final effectiveIconColor = isActive
        ? (activeColor ?? (isDestructive ? destructiveColor : accentColor))
        : normalColor;

    // Effective background color for active state
    material.Color? effectiveBgColor;
    if (isActive) {
      effectiveBgColor = isDestructive
          ? destructiveColor.withValues(alpha: 0.16)
          : accentColor.withValues(alpha: 0.14);
    }

    final hoverColor = isDestructive
        ? destructiveColor.withValues(alpha: 0.12)
        : cs.muted.withValues(alpha: 0.35);

    material.Widget button = material.Material(
      color: effectiveBgColor ?? material.Colors.transparent,
      shape: material.RoundedRectangleBorder(
        borderRadius: radius,
        side: _focused
            ? material.BorderSide(color: cs.ring, width: 2)
            : isActive
                ? material.BorderSide(
                    color: (isDestructive ? destructiveColor : accentColor)
                        .withValues(alpha: 0.3),
                    width: 1,
                  )
                : material.BorderSide.none,
      ),
      clipBehavior: material.Clip.antiAlias,
      child: material.InkWell(
        onTap: onPressed,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        borderRadius: radius,
        hoverColor: hoverColor,
        focusColor: material.Colors.transparent,
        splashColor: (isDestructive ? destructiveColor : accentColor)
            .withValues(alpha: 0.2),
        child: material.SizedBox(
          width: boxSize,
          height: boxSize,
          child: material.Center(
            child: material.IconTheme(
              data: material.IconThemeData(
                size: iconSize,
                color: isEnabled
                    ? effectiveIconColor
                    : mutedColor.withValues(alpha: 0.4),
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );

    button = material.Semantics(
      button: true,
      enabled: onPressed != null,
      selected: isActive,
      child: button,
    );

    if (tooltip != null && tooltip.isNotEmpty) {
      button = material.Tooltip(
        message: tooltip,
        waitDuration: kQueryaTooltipWait,
        child: button,
      );
    }

    return button;
  }
}

/// Standard toolbar button with optional leading icon, label, and shortcut hint.
class QueryaToolbarButton extends material.StatefulWidget {
  const QueryaToolbarButton({
    super.key,
    required this.label,
    this.icon,
    this.tooltip,
    this.shortcutHint,
    this.onPressed,
    this.density,
    this.size,
    this.isActive = false,
    this.isDestructive = false,
  });

  final String label;
  final material.Widget? icon;
  final String? tooltip;
  final String? shortcutHint;
  final material.VoidCallback? onPressed;

  /// Legacy size name; [size] wins when both are set.
  final QueryaIconButtonDensity? density;

  /// Control size; see [QueryaIconButton.size].
  final QueryaControlSize? size;
  final bool isActive;
  final bool isDestructive;

  @override
  material.State<QueryaToolbarButton> createState() =>
      _QueryaToolbarButtonState();
}

class _QueryaToolbarButtonState extends material.State<QueryaToolbarButton> {
  /// Whether the button has keyboard focus (#1370): drawn as a 2px ring.
  bool _focused = false;

  @override
  material.Widget build(material.BuildContext context) {
    final label = widget.label;
    final icon = widget.icon;
    final tooltip = widget.tooltip;
    final shortcutHint = widget.shortcutHint;
    final onPressed = widget.onPressed;
    final controlSize = widget.size ??
        widget.density?.controlSize ??
        QueryaControlSize.of(context);
    final isActive = widget.isActive;
    final isDestructive = widget.isDestructive;
    final cs = Theme.of(context).colorScheme;
    final workbench = QueryaThemeScope.maybeOf(context)?.workbench;
    final isEnabled = onPressed != null;

    final destructiveColor = workbench?.destructive ?? cs.destructive;
    final accentColor = workbench?.accent ?? cs.primary;
    final radius =
        material.BorderRadius.circular(controlSize.scaledRadius(context));

    final effectiveFgColor = isActive
        ? (isDestructive ? destructiveColor : accentColor)
        : (isDestructive
            ? destructiveColor
            : (isEnabled ? cs.foreground : cs.mutedForeground.withValues(alpha: 0.5)));

    final effectiveBgColor = isActive
        ? (isDestructive
            ? destructiveColor.withValues(alpha: 0.16)
            : accentColor.withValues(alpha: 0.14))
        : material.Colors.transparent;

    final hoverColor = isDestructive
        ? destructiveColor.withValues(alpha: 0.12)
        : cs.muted.withValues(alpha: 0.35);

    material.Widget content = material.Row(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          material.IconTheme(
            data: material.IconThemeData(
              size: controlSize.scaledIconSize(context),
              color: effectiveFgColor,
            ),
            child: icon,
          ),
          Gap(controlSize.scaledIconGap(context)),
        ],
        material.Text(
          label,
          style: material.TextStyle(
            fontSize: controlSize.scaledFontSize(context),
            fontWeight: material.FontWeight.w500,
            color: effectiveFgColor,
          ),
        ),
        if (shortcutHint != null) ...[
          const Gap(6),
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.4),
              borderRadius: material.BorderRadius.circular(3),
            ),
            child: material.Text(
              shortcutHint,
              style: material.TextStyle(
                fontSize: 9,
                fontWeight: material.FontWeight.w500,
                color: cs.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );

    material.Widget button = material.Material(
      color: effectiveBgColor,
      shape: material.RoundedRectangleBorder(
        borderRadius: radius,
        side: _focused
            ? material.BorderSide(color: cs.ring, width: 2)
            : isActive
                ? material.BorderSide(
                    color: (isDestructive ? destructiveColor : accentColor)
                        .withValues(alpha: 0.3),
                    width: 1,
                  )
                : material.BorderSide.none,
      ),
      clipBehavior: material.Clip.antiAlias,
      child: material.InkWell(
        onTap: onPressed,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        borderRadius: radius,
        hoverColor: hoverColor,
        focusColor: material.Colors.transparent,
        child: material.Container(
          height: controlSize.scaledHeight(context),
          padding: material.EdgeInsets.symmetric(
            horizontal: controlSize.scaledHorizontalPadding(context),
          ),
          alignment: material.Alignment.center,
          child: content,
        ),
      ),
    );

    button = material.Semantics(
      button: true,
      enabled: onPressed != null,
      selected: isActive,
      child: button,
    );

    if (tooltip != null && tooltip.isNotEmpty) {
      button = material.Tooltip(
        message: tooltip,
        waitDuration: kQueryaTooltipWait,
        child: button,
      );
    }

    return button;
  }
}
