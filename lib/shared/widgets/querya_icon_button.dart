import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';

/// Icon-only button of the Querya kit, a thin wrapper over [QueryaButton]
/// (#1440): the same states as every other button (hover, pressed,
/// keyboard-only focus ring, disabled, `selected` semantics), square at its
/// [QueryaControlSize].
///
/// [icon] is a plain `Icon`: its glyph is used, the size and colour come from
/// the control size and the button's state. [isActive] tints it with the
/// accent, [isDestructive] with the destructive colour.
class QueryaIconButton extends material.StatelessWidget {
  const QueryaIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.size,
    this.isActive = false,
    this.isDestructive = false,
    this.borderRadius,
  });

  /// The `Icon` to render.
  final material.Icon icon;

  /// Shown on hover after [kQueryaTooltipWait]; also the spoken label.
  final String? tooltip;

  /// Callback when pressed. If null, the button is disabled.
  final material.VoidCallback? onPressed;

  /// Control size. Without one the button takes the nearest
  /// [QueryaControlScope], then [QueryaControlSize.md].
  final QueryaControlSize? size;

  /// Whether the button is currently in an active/toggled state.
  final bool isActive;

  /// Whether clicking triggers a destructive action.
  final bool isDestructive;

  /// Custom border radius; defaults to the control size's radius.
  final material.BorderRadius? borderRadius;

  @override
  material.Widget build(material.BuildContext context) {
    final glyph = icon.icon;
    assert(glyph != null, 'QueryaIconButton needs an Icon with a glyph');
    return QueryaButton(
      variant: QueryaButtonVariant.ghost,
      icon: glyph,
      tooltip: tooltip,
      semanticLabel: tooltip,
      onPressed: onPressed,
      isActive: isActive,
      size: size,
      tone: isDestructive
          ? QueryaButtonTone.destructive
          : QueryaButtonTone.normal,
      borderRadius: borderRadius,
    );
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
    this.size,
    this.isActive = false,
    this.isDestructive = false,
  });

  final String label;
  final material.Widget? icon;
  final String? tooltip;
  final String? shortcutHint;
  final material.VoidCallback? onPressed;

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
        QueryaControlSize.of(context);
    final isActive = widget.isActive;
    final isDestructive = widget.isDestructive;
    final cs = context.colors;
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
          material.SizedBox(width: controlSize.scaledIconGap(context)),
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
          const material.SizedBox(width: 6),
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
