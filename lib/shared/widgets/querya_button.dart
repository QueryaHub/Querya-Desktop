import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';

/// The role of a [QueryaButton] (docs/ui-kit.md, "Variants").
enum QueryaButtonVariant {
  /// Filled with the workbench accent: the main action of a surface.
  primary,

  /// Outlined, neutral: ordinary actions.
  secondary,

  /// No fill, no outline: Cancel, Close, tertiary and toolbar actions.
  ghost,

  /// Filled with the workbench destructive colour: irreversible actions.
  destructive,
}

/// Colour of the label and icon of a [QueryaButtonVariant.secondary] or
/// [QueryaButtonVariant.ghost] button.
enum QueryaButtonTone {
  /// The theme's foreground.
  normal,

  /// The workbench destructive colour (red text, red outline for secondary).
  destructive,
}

/// The Querya button: one control scale, four variants, own states, no
/// `shadcn_flutter` (epic #1331).
///
/// ```dart
/// QueryaButton.primary(label: 'Save', onPressed: _save)
/// QueryaButton.secondary(label: 'Explain', icon: Icons.account_tree_outlined, onPressed: _explain)
/// QueryaButton.ghost(label: 'Cancel', onPressed: _close)
/// QueryaButton.destructive(label: 'Delete', onPressed: _delete)
/// QueryaButton.icon(icon: Icons.refresh, tooltip: 'Refresh', onPressed: _reload)
/// ```
///
/// - Height, padding, font and icon size come from [QueryaControlSize]: the
///   explicit [size], else the nearest [QueryaControlScope], else `md`.
/// - `onPressed: null` disables the button. While [loading] it keeps its width
///   (the spinner takes the icon's place, or covers the hidden label) and does
///   not fire.
/// - Enter and Space activate a focused button; the focus ring shows only for
///   keyboard focus.
/// - The label never wraps: it ellipsizes.
class QueryaButton extends material.StatefulWidget {
  const QueryaButton._({
    super.key,
    required this.variant,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.trailing,
    this.shortcutHint,
    this.loading = false,
    this.tooltip,
    this.isActive = false,
    this.compact = false,
    this.autofocus = false,
    this.semanticLabel,
    this.size,
    this.tone = QueryaButtonTone.normal,
  }) : assert(
          label != null || icon != null,
          'A QueryaButton needs a label, an icon, or both',
        );

  /// The main action: filled with the accent.
  const QueryaButton.primary({
    Key? key,
    required String label,
    material.VoidCallback? onPressed,
    material.IconData? icon,
    material.Widget? trailing,
    String? shortcutHint,
    bool loading = false,
    String? tooltip,
    bool compact = false,
    bool autofocus = false,
    String? semanticLabel,
    QueryaControlSize? size,
  }) : this._(
          key: key,
          variant: QueryaButtonVariant.primary,
          label: label,
          icon: icon,
          onPressed: onPressed,
          trailing: trailing,
          shortcutHint: shortcutHint,
          loading: loading,
          tooltip: tooltip,
          compact: compact,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
          size: size,
        );

  /// An ordinary action: outlined.
  const QueryaButton.secondary({
    Key? key,
    required String label,
    material.VoidCallback? onPressed,
    material.IconData? icon,
    material.Widget? trailing,
    String? shortcutHint,
    bool loading = false,
    String? tooltip,
    bool isActive = false,
    bool compact = false,
    bool autofocus = false,
    String? semanticLabel,
    QueryaControlSize? size,
    QueryaButtonTone tone = QueryaButtonTone.normal,
  }) : this._(
          key: key,
          variant: QueryaButtonVariant.secondary,
          label: label,
          icon: icon,
          onPressed: onPressed,
          trailing: trailing,
          shortcutHint: shortcutHint,
          loading: loading,
          tooltip: tooltip,
          isActive: isActive,
          compact: compact,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
          size: size,
          tone: tone,
        );

  /// Cancel, Close and tertiary actions: no fill, no outline.
  const QueryaButton.ghost({
    Key? key,
    required String label,
    material.VoidCallback? onPressed,
    material.IconData? icon,
    material.Widget? trailing,
    String? shortcutHint,
    bool loading = false,
    String? tooltip,
    bool isActive = false,
    bool compact = false,
    bool autofocus = false,
    String? semanticLabel,
    QueryaControlSize? size,
    QueryaButtonTone tone = QueryaButtonTone.normal,
  }) : this._(
          key: key,
          variant: QueryaButtonVariant.ghost,
          label: label,
          icon: icon,
          onPressed: onPressed,
          trailing: trailing,
          shortcutHint: shortcutHint,
          loading: loading,
          tooltip: tooltip,
          isActive: isActive,
          compact: compact,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
          size: size,
          tone: tone,
        );

  /// An irreversible action: filled with the destructive colour.
  const QueryaButton.destructive({
    Key? key,
    required String label,
    material.VoidCallback? onPressed,
    material.IconData? icon,
    material.Widget? trailing,
    String? shortcutHint,
    bool loading = false,
    String? tooltip,
    bool compact = false,
    bool autofocus = false,
    String? semanticLabel,
    QueryaControlSize? size,
  }) : this._(
          key: key,
          variant: QueryaButtonVariant.destructive,
          label: label,
          icon: icon,
          onPressed: onPressed,
          trailing: trailing,
          shortcutHint: shortcutHint,
          loading: loading,
          tooltip: tooltip,
          compact: compact,
          autofocus: autofocus,
          semanticLabel: semanticLabel,
          size: size,
        );

  /// An icon-only button: square, with a tooltip that doubles as its label.
  const QueryaButton.icon({
    Key? key,
    required material.IconData icon,
    required String tooltip,
    material.VoidCallback? onPressed,
    bool loading = false,
    bool isActive = false,
    bool autofocus = false,
    QueryaControlSize? size,
    QueryaButtonTone tone = QueryaButtonTone.normal,
  }) : this._(
          key: key,
          variant: QueryaButtonVariant.ghost,
          label: null,
          icon: icon,
          onPressed: onPressed,
          loading: loading,
          tooltip: tooltip,
          isActive: isActive,
          autofocus: autofocus,
          semanticLabel: tooltip,
          size: size,
          tone: tone,
        );

  final QueryaButtonVariant variant;

  /// The text; null for an icon-only button.
  final String? label;
  final material.IconData? icon;

  /// `null` disables the button.
  final material.VoidCallback? onPressed;

  /// A widget after the label (a chevron, a badge).
  final material.Widget? trailing;

  /// A keyboard hint drawn as a small chip after the label.
  final String? shortcutHint;

  /// Shows a spinner, keeps the width and ignores presses.
  final bool loading;

  /// Shown on hover after [kQueryaTooltipWait].
  final String? tooltip;

  /// A toggled-on state for [QueryaButtonVariant.secondary] and
  /// [QueryaButtonVariant.ghost]: accent-tinted background and accent text.
  final bool isActive;

  /// Hides the label and keeps the icon (narrow toolbars); the label becomes
  /// the tooltip when none is set. Without an [icon] it has no effect.
  final bool compact;
  final bool autofocus;

  /// Spoken label; defaults to the label, then the tooltip.
  final String? semanticLabel;

  /// Control size; see the class documentation.
  final QueryaControlSize? size;

  /// See [QueryaButtonTone]; ignored by the filled variants.
  final QueryaButtonTone tone;

  @override
  material.State<QueryaButton> createState() => _QueryaButtonState();
}

class _QueryaButtonState extends material.State<QueryaButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _keyboardFocus = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  /// Black or white, whichever reads on [background].
  static material.Color _onColor(material.Color background) =>
      background.computeLuminance() > 0.5
          ? const material.Color(0xFF000000)
          : const material.Color(0xFFFFFFFF);

  @override
  material.Widget build(material.BuildContext context) {
    final w = widget;
    final wb = context.workbench;
    final scheme = context.queryaTheme.colorScheme;
    final size = w.size ?? QueryaControlSize.of(context);
    final enabled = _enabled;
    final hasLabel = w.label != null;
    final iconOnly = !hasLabel || (w.compact && w.icon != null);
    final filled = w.variant == QueryaButtonVariant.primary ||
        w.variant == QueryaButtonVariant.destructive;

    // ---- colours -------------------------------------------------------
    final material.Color foreground;
    material.Color background;
    var outline = const material.Color(0x00000000);
    if (filled) {
      final base = w.variant == QueryaButtonVariant.primary
          ? wb.accent
          : wb.destructive;
      foreground = w.variant == QueryaButtonVariant.primary
          ? wb.onAccent
          : _onColor(base);
      final tint = _pressed && enabled
          ? 0.22
          : (_hovered && enabled ? 0.12 : 0.0);
      background =
          material.Color.alphaBlend(foreground.withValues(alpha: tint), base);
    } else {
      final toneColor = w.tone == QueryaButtonTone.destructive
          ? wb.destructive
          : scheme.foreground;
      if (w.isActive) {
        foreground = wb.accent;
        background = wb.accent.withValues(alpha: _pressed ? 0.22 : 0.14);
      } else {
        foreground = toneColor;
        final tint = _pressed && enabled
            ? 0.16
            : (_hovered && enabled ? 0.08 : 0.0);
        background = toneColor.withValues(alpha: tint);
      }
      if (w.variant == QueryaButtonVariant.secondary) {
        outline = w.tone == QueryaButtonTone.destructive
            ? wb.destructive.withValues(alpha: 0.6)
            : wb.borderSubtle;
      }
    }

    // ---- content -------------------------------------------------------
    final iconSize = size.scaledIconSize(context);
    final fontSize = size.scaledFontSize(context);
    final gap = size.scaledIconGap(context);

    material.Widget? leading;
    if (w.loading && w.icon != null) {
      leading = QueryaSpinner(customDimension: iconSize, color: foreground);
    } else if (w.icon != null) {
      leading = material.Icon(w.icon, size: iconSize, color: foreground);
    }

    final children = <material.Widget>[
      if (leading != null) leading,
      if (!iconOnly) ...[
        if (leading != null) material.SizedBox(width: gap),
        material.Flexible(
          child: material.Text(
            w.label!,
            maxLines: 1,
            overflow: material.TextOverflow.ellipsis,
            softWrap: false,
            style: material.TextStyle(
              fontSize: fontSize,
              fontWeight: material.FontWeight.w500,
              height: 1.2,
              color: foreground,
            ),
          ),
        ),
        if (w.shortcutHint != null) ...[
          material.SizedBox(width: gap),
          material.DecoratedBox(
            decoration: material.BoxDecoration(
              color: foreground.withValues(alpha: 0.14),
              borderRadius: material.BorderRadius.circular(3),
            ),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 1,
              ),
              child: material.Text(
                w.shortcutHint!,
                style: material.TextStyle(
                  fontSize: fontSize * 0.75,
                  fontWeight: material.FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
          ),
        ],
        if (w.trailing != null) ...[
          material.SizedBox(width: gap),
          w.trailing!,
        ],
      ],
    ];

    material.Widget content = material.Row(
      mainAxisSize: material.MainAxisSize.min,
      mainAxisAlignment: material.MainAxisAlignment.center,
      crossAxisAlignment: material.CrossAxisAlignment.center,
      children: children,
    );

    // Loading without an icon: keep the label's width, spinner on top.
    if (w.loading && w.icon == null) {
      content = material.Stack(
        alignment: material.Alignment.center,
        children: [
          material.Opacity(opacity: 0, child: content),
          QueryaSpinner(customDimension: iconSize, color: foreground),
        ],
      );
    }

    final height = size.scaledHeight(context);
    final radius = material.BorderRadius.circular(size.scaledRadius(context));
    final ring = scheme.ring;

    material.Widget button = material.AnimatedContainer(
      duration: context.motionDuration(QueryaMotion.fast),
      curve: context.motionCurve(QueryaMotion.enter),
      height: height,
      constraints: iconOnly ? material.BoxConstraints(minWidth: height) : null,
      padding: iconOnly
          ? material.EdgeInsets.zero
          : material.EdgeInsets.symmetric(
              horizontal: size.scaledHorizontalPadding(context),
            ),
      decoration: material.BoxDecoration(
        color: background,
        borderRadius: radius,
        border: material.Border.all(color: outline),
      ),
      foregroundDecoration: _keyboardFocus
          ? material.BoxDecoration(
              borderRadius: radius,
              border: material.Border.all(color: ring, width: 2),
            )
          : null,
      child: material.Center(
        widthFactor: 1,
        child: content,
      ),
    );

    if (w.onPressed == null) {
      button = material.Opacity(opacity: 0.5, child: button);
    }

    button = material.GestureDetector(
      behavior: material.HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? _activate : null,
      child: button,
    );

    button = material.FocusableActionDetector(
      enabled: enabled,
      autofocus: w.autofocus,
      mouseCursor: enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      shortcuts: const {
        material.SingleActivator(LogicalKeyboardKey.enter):
            material.ActivateIntent(),
        material.SingleActivator(LogicalKeyboardKey.space):
            material.ActivateIntent(),
      },
      actions: {
        material.ActivateIntent: material.CallbackAction<material.ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (value) {
        if (_hovered != value) setState(() => _hovered = value);
      },
      onShowFocusHighlight: (value) {
        if (_keyboardFocus != value) setState(() => _keyboardFocus = value);
      },
      child: button,
    );

    final hint = (w.tooltip != null && w.tooltip!.isNotEmpty)
        ? w.tooltip
        : (iconOnly && hasLabel ? w.label : null);
    if (hint != null) {
      button = material.Tooltip(
        message: hint,
        waitDuration: kQueryaTooltipWait,
        excludeFromSemantics: true,
        child: button,
      );
    }

    return material.Semantics(
      button: true,
      enabled: enabled,
      selected: w.isActive,
      label: w.semanticLabel ?? w.label ?? w.tooltip,
      hint: w.loading ? 'Loading' : null,
      onTap: enabled ? _activate : null,
      excludeSemantics: true,
      child: button,
    );
  }
}
