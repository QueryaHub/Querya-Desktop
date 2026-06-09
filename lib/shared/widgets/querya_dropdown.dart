import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

export 'querya_dropdown_tokens.dart';

/// One selectable row in [QueryaDropdown].
class QueryaDropdownItem<T> {
  const QueryaDropdownItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.leading,
  });

  final T value;
  final String label;
  final bool enabled;
  final material.Widget? leading;
}

/// Stable dropdown built on [material.MenuAnchor] (no Overlay portal).
///
/// Visual metrics: [QueryaDropdownTokens]. Colors from shadcn [ColorScheme].
class QueryaDropdown<T> extends material.StatefulWidget {
  const QueryaDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onSelected,
    this.controller,
    this.enabled = true,
    this.width,
    this.expandToParent = false,
    this.alignmentOffset = QueryaDropdownTokens.menuAlignmentOffset,
    this.menuMaxHeight = QueryaDropdownTokens.menuMaxHeight,
    this.hint,
  });

  final T value;
  final List<QueryaDropdownItem<T>> items;
  final material.ValueChanged<T?> onSelected;
  final material.MenuController? controller;
  final bool enabled;
  final double? width;
  final bool expandToParent;
  final material.Offset alignmentOffset;
  final double menuMaxHeight;
  final String? hint;

  @override
  material.State<QueryaDropdown<T>> createState() => _QueryaDropdownState<T>();
}

class _QueryaDropdownState<T> extends material.State<QueryaDropdown<T>> {
  late material.MenuController _controller;
  bool _triggerHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? material.MenuController();
  }

  @override
  void didUpdateWidget(covariant QueryaDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? material.MenuController();
    }
  }

  material.Widget _triggerLabelText({
    required String label,
    required ColorScheme cs,
    required bool expand,
  }) {
    final text = material.Text(
      label,
      maxLines: 1,
      overflow: material.TextOverflow.ellipsis,
      style: material.TextStyle(
        fontSize: QueryaDropdownTokens.fontSize,
        fontWeight: material.FontWeight.w500,
        color: widget.enabled ? cs.foreground : cs.mutedForeground,
      ),
    );
    if (expand) {
      return material.Expanded(child: text);
    }
    return text;
  }

  String _labelFor(T value) {
    for (final item in widget.items) {
      if (item.value == value) return item.label;
    }
    return widget.hint ?? '';
  }

  material.Widget _menuItem(QueryaDropdownItem<T> item, ColorScheme cs) {
    return _QueryaDropdownMenuItem<T>(
      item: item,
      selected: item.value == widget.value,
      enabled: widget.enabled && item.enabled,
      colorScheme: cs,
      onPick: () {
        widget.onSelected(item.value);
        _controller.close();
      },
    );
  }

  material.Widget _buildTrigger({
    required material.BuildContext context,
    required material.MenuController controller,
    required ColorScheme cs,
    required String label,
    required double? fieldWidth,
  }) {
    final borderColor = widget.enabled
        ? (_triggerHovered ? cs.ring : cs.border)
        : cs.border.withValues(alpha: 0.4);

    final triggerBody = material.MouseRegion(
      cursor: widget.enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _triggerHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _triggerHovered = false) : null,
      child: material.AnimatedContainer(
        duration: const Duration(
          milliseconds: QueryaDropdownTokens.hoverAnimationMs,
        ),
        curve: material.Curves.easeOut,
        height: QueryaDropdownTokens.triggerHeight,
        padding: QueryaDropdownTokens.triggerPadding,
        decoration: material.BoxDecoration(
          color: _triggerHovered
              ? cs.muted.withValues(alpha: 0.22)
              : cs.muted.withValues(alpha: 0.08),
          borderRadius: material.BorderRadius.circular(
            QueryaDropdownTokens.menuBorderRadius,
          ),
          border: material.Border.all(color: borderColor),
        ),
        child: material.Row(
          mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
          mainAxisSize:
              widget.expandToParent ? material.MainAxisSize.max : material.MainAxisSize.min,
          children: [
            _triggerLabelText(label: label, cs: cs, expand: widget.expandToParent),
            const material.SizedBox(width: QueryaDropdownTokens.triggerChevronGap),
            material.Icon(
              material.Icons.keyboard_arrow_down_rounded,
              size: QueryaDropdownTokens.triggerChevronSize,
              color: widget.enabled
                  ? cs.mutedForeground
                  : cs.mutedForeground.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );

    return material.Material(
      type: material.MaterialType.transparency,
      child: material.InkWell(
        onTap: widget.enabled
            ? () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              }
            : null,
        borderRadius: material.BorderRadius.circular(
          QueryaDropdownTokens.menuBorderRadius,
        ),
        child: fieldWidth != null
            ? material.SizedBox(width: fieldWidth, child: triggerBody)
            : triggerBody,
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = _labelFor(widget.value);
    final fieldWidth = widget.expandToParent ? null : widget.width;
    final menuChildren = widget.items.map((item) => _menuItem(item, cs)).toList();
    final effectiveMaxHeight = widget.items.length > QueryaDropdownTokens.menuScrollItemThreshold
        ? widget.menuMaxHeight
        : double.infinity;

    final anchor = material.MenuAnchor(
      controller: _controller,
      alignmentOffset: widget.alignmentOffset,
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
        maximumSize: material.WidgetStatePropertyAll(
          material.Size(double.infinity, effectiveMaxHeight),
        ),
        padding: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuPadding,
        ),
        shape: material.WidgetStatePropertyAll(
          material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(
              QueryaDropdownTokens.menuBorderRadius,
            ),
            side: material.BorderSide(color: cs.border),
          ),
        ),
      ),
      menuChildren: menuChildren,
      builder: (context, controller, child) {
        final trigger = _buildTrigger(
          context: context,
          controller: controller,
          cs: cs,
          label: label,
          fieldWidth: fieldWidth,
        );
        if (widget.expandToParent) {
          return material.SizedBox(width: double.infinity, child: trigger);
        }
        return trigger;
      },
    );

    if (fieldWidth != null && !widget.expandToParent) {
      return material.SizedBox(width: fieldWidth, child: anchor);
    }
    return anchor;
  }
}

class _QueryaDropdownMenuItem<T> extends material.StatefulWidget {
  const _QueryaDropdownMenuItem({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.colorScheme,
    required this.onPick,
  });

  final QueryaDropdownItem<T> item;
  final bool selected;
  final bool enabled;
  final ColorScheme colorScheme;
  final material.VoidCallback onPick;

  @override
  material.State<_QueryaDropdownMenuItem<T>> createState() =>
      _QueryaDropdownMenuItemState<T>();
}

class _QueryaDropdownMenuItemState<T> extends material.State<_QueryaDropdownMenuItem<T>> {
  bool _hovered = false;

  material.Widget _leading(ColorScheme cs) {
    if (widget.selected) {
      return material.Icon(
        material.Icons.check_rounded,
        size: QueryaDropdownTokens.selectedCheckSize,
        color: cs.primary,
      );
    }
    if (widget.item.leading != null) {
      return widget.item.leading!;
    }
    return const material.SizedBox(width: QueryaDropdownTokens.selectedCheckSlotWidth);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = widget.colorScheme;
    final bg = _hovered
        ? cs.accent.withValues(alpha: 0.12)
        : widget.selected
            ? cs.muted.withValues(alpha: 0.28)
            : material.Colors.transparent;

    return material.MouseRegion(
      cursor: widget.enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: material.MenuItemButton(
        style: material.MenuItemButton.styleFrom(
          minimumSize: const material.Size(
            QueryaDropdownTokens.menuItemMinWidth,
            QueryaDropdownTokens.menuItemHeight,
          ),
          padding: material.EdgeInsets.zero,
          foregroundColor: cs.popoverForeground,
          disabledForegroundColor: cs.mutedForeground.withValues(alpha: 0.5),
          overlayColor: material.Colors.transparent,
          shape: material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(
              QueryaDropdownTokens.menuBorderRadius,
            ),
          ),
        ),
        onPressed: widget.enabled ? widget.onPick : null,
        child: material.AnimatedContainer(
          duration: const Duration(
          milliseconds: QueryaDropdownTokens.hoverAnimationMs,
        ),
          curve: material.Curves.easeOut,
          padding: QueryaDropdownTokens.menuItemPadding,
          decoration: material.BoxDecoration(
            color: bg,
            borderRadius: material.BorderRadius.circular(
              QueryaDropdownTokens.menuBorderRadius,
            ),
          ),
          child: material.Row(
            children: [
              material.SizedBox(
                width: QueryaDropdownTokens.selectedCheckSlotWidth,
                child: _leading(cs),
              ),
              const material.SizedBox(width: 6),
              material.Expanded(
                child: material.Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: material.TextStyle(
                    fontSize: QueryaDropdownTokens.fontSize,
                    fontWeight: widget.selected
                        ? material.FontWeight.w600
                        : material.FontWeight.w400,
                    color: cs.popoverForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
