import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// One command row in [QueryaActionMenu].
class QueryaActionMenuItem<T> {
  const QueryaActionMenuItem({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final material.IconData? icon;
}

/// "Button that opens a list of commands" (Export / Copy).
///
/// Same popup surface as `QueryaDropdown` (border, radius, soft shadow,
/// compact rows, no ripple); trigger is a regular shadcn [OutlineButton].
class QueryaActionMenu<T> extends material.StatelessWidget {
  const QueryaActionMenu({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  final List<QueryaActionMenuItem<T>> items;
  final material.ValueChanged<T> onSelected;

  /// Trigger content (label / icon row).
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);
    return material.MenuAnchor(
      alignmentOffset: material.Offset(
        0,
        context.scaled(QueryaDropdownTokens.menuAlignmentOffset.dy),
      ),
      consumeOutsideTap: true,
      style: material.MenuStyle(
        backgroundColor: material.WidgetStatePropertyAll(cs.popover),
        surfaceTintColor: material.WidgetStatePropertyAll(cs.popover),
        elevation: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuElevation,
        ),
        shadowColor: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuShadowColor,
        ),
        padding: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuPadding,
        ),
        shape: material.WidgetStatePropertyAll(
          material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(radius),
            side: material.BorderSide(color: cs.border),
          ),
        ),
      ),
      menuChildren: [
        for (final item in items)
          material.MenuItemButton(
            style: material.MenuItemButton.styleFrom(
              minimumSize: material.Size(
                0,
                QueryaDropdownTokens.scaledMenuItemHeight(context),
              ),
              padding: material.EdgeInsets.symmetric(
                horizontal: context.scaled(8),
              ),
              foregroundColor: cs.popoverForeground,
              overlayColor: cs.accent.withValues(alpha: 0.14),
              shape: material.RoundedRectangleBorder(
                borderRadius: material.BorderRadius.circular(radius),
              ),
            ),
            leadingIcon: item.icon == null
                ? null
                : material.Icon(
                    item.icon,
                    size: context.scaled(16),
                    color: cs.mutedForeground,
                  ),
            onPressed: () => onSelected(item.value),
            child: material.Text(
              item.label,
              style: QueryaDropdownTokens.menuItemTextStyle(
                context,
                cs.popoverForeground,
                selected: false,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => OutlineButton(
        size: ButtonSize.small,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: child,
      ),
    );
  }
}
