import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Labelled outline button for toolbars: optional leading icon, a [loading]
/// state with a spinner, and a destructive tone.
///
/// While [loading] the button is disabled and shows a [QueryaSpinner] in place
/// of [icon]. Icon and spinner follow the workbench accent, or the destructive
/// color when [isDestructive] is set.
class QueryaActionButton extends material.StatelessWidget {
  const QueryaActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.isDestructive = false,
    this.tooltip,
    this.size = ButtonSize.normal,
  });

  final String label;
  final material.IconData? icon;

  /// `null` disables the button.
  final material.VoidCallback? onPressed;

  /// Shows a spinner instead of [icon] and disables the button.
  final bool loading;

  /// Uses the destructive color for the icon and the label.
  final bool isDestructive;

  /// Shown on hover after [kQueryaTooltipWait].
  final String? tooltip;
  final ButtonSize size;

  @override
  material.Widget build(material.BuildContext context) {
    final workbench = context.workbench;
    final tone = isDestructive ? workbench.destructive : workbench.accent;
    final enabled = onPressed != null && !loading;

    material.Widget? leading;
    if (loading) {
      leading = QueryaSpinner(size: QueryaSpinnerSize.sm, color: tone);
    } else if (icon != null) {
      leading = material.Icon(icon, size: 18, color: tone);
    }

    material.Widget button = OutlineButton(
      size: size,
      onPressed: enabled ? onPressed : null,
      leading: leading,
      child: isDestructive
          ? Text(label, style: material.TextStyle(color: tone))
          : Text(label),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = material.Tooltip(
        message: tooltip!,
        waitDuration: kQueryaTooltipWait,
        child: button,
      );
    }
    return button;
  }
}
