import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
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
  List<material.Widget>? _cachedMenuChildren;
  List<QueryaDropdownItem<T>>? _cachedMenuItems;
  T? _cachedMenuValue;

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
    if (!listEquals(oldWidget.items, widget.items) ||
        oldWidget.value != widget.value) {
      _cachedMenuChildren = null;
    }
  }

  List<material.Widget> _menuChildren(ColorScheme cs) {
    if (_cachedMenuChildren != null &&
        listEquals(_cachedMenuItems, widget.items) &&
        _cachedMenuValue == widget.value) {
      return _cachedMenuChildren!;
    }
    _cachedMenuItems = List<QueryaDropdownItem<T>>.from(widget.items);
    _cachedMenuValue = widget.value;
    _cachedMenuChildren =
        widget.items.map((item) => _menuItem(item, cs)).toList();
    return _cachedMenuChildren!;
  }

  material.Widget _triggerLabelText({
    required material.BuildContext context,
    required String label,
    required ColorScheme cs,
    required bool expand,
  }) {
    final textColor =
        widget.enabled ? cs.popoverForeground : cs.mutedForeground;
    final text = material.Text(
      label,
      maxLines: 1,
      overflow: material.TextOverflow.ellipsis,
      style: QueryaDropdownTokens.triggerTextStyle(context, textColor),
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
    final triggerHeight = QueryaDropdownTokens.scaledTriggerHeight(context);
    final chevronGap = context.scaled(QueryaDropdownTokens.triggerChevronGap);
    final chevronSize = context.scaled(QueryaDropdownTokens.triggerChevronSize);
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

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
        height: triggerHeight,
        padding: QueryaDropdownTokens.scaledTriggerPadding(context),
        decoration: material.BoxDecoration(
          color: _triggerHovered
              ? cs.muted.withValues(alpha: 0.28)
              : cs.muted.withValues(alpha: 0.14),
          borderRadius: material.BorderRadius.circular(radius),
          border: material.Border.all(color: borderColor),
        ),
        child: material.Row(
          mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
          mainAxisSize: (widget.expandToParent || fieldWidth != null)
              ? material.MainAxisSize.max
              : material.MainAxisSize.min,
          children: [
            _triggerLabelText(
              context: context,
              label: label,
              cs: cs,
              expand: widget.expandToParent || fieldWidth != null,
            ),
            material.SizedBox(width: chevronGap),
            material.Icon(
              material.Icons.keyboard_arrow_down_rounded,
              size: chevronSize,
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
        borderRadius: material.BorderRadius.circular(radius),
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
    final fieldWidth = widget.expandToParent
        ? null
        : (widget.width != null ? context.scaled(widget.width!) : null);
    final menuChildren = _menuChildren(cs);
    final scaledMaxHeight = context.scaled(widget.menuMaxHeight);
    final effectiveMaxHeight =
        widget.items.length > QueryaDropdownTokens.menuScrollItemThreshold
            ? scaledMaxHeight
            : double.infinity;
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

    final anchor = material.MenuAnchor(
      controller: _controller,
      crossAxisUnconstrained: false,
      alignmentOffset: material.Offset(
        widget.alignmentOffset.dx,
        context.scaled(widget.alignmentOffset.dy),
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
        maximumSize: material.WidgetStatePropertyAll(
          material.Size(double.infinity, effectiveMaxHeight),
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

  material.Widget _leading(material.BuildContext context, ColorScheme cs) {
    final slot = context.scaled(QueryaDropdownTokens.selectedCheckSlotWidth);
    final checkSize = context.scaled(QueryaDropdownTokens.selectedCheckSize);
    if (widget.selected) {
      return material.Icon(
        material.Icons.check_rounded,
        size: checkSize,
        color: cs.primary,
      );
    }
    if (widget.item.leading != null) {
      return widget.item.leading!;
    }
    return material.SizedBox(width: slot);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = widget.colorScheme;
    final bg = _hovered
        ? cs.accent.withValues(alpha: 0.14)
        : widget.selected
            ? cs.muted.withValues(alpha: 0.32)
            : material.Colors.transparent;
    final itemHeight = QueryaDropdownTokens.scaledMenuItemHeight(context);
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);
    final slot = context.scaled(QueryaDropdownTokens.selectedCheckSlotWidth);

    return material.MouseRegion(
      cursor: widget.enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: material.MenuItemButton(
        style: material.MenuItemButton.styleFrom(
          minimumSize: material.Size(double.infinity, itemHeight),
          padding: material.EdgeInsets.zero,
          foregroundColor: cs.popoverForeground,
          disabledForegroundColor: cs.mutedForeground.withValues(alpha: 0.5),
          overlayColor: material.Colors.transparent,
          shape: material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(radius),
          ),
        ),
        onPressed: widget.enabled ? widget.onPick : null,
        child: material.AnimatedContainer(
          duration: const Duration(
            milliseconds: QueryaDropdownTokens.hoverAnimationMs,
          ),
          curve: material.Curves.easeOut,
          constraints: material.BoxConstraints(minHeight: itemHeight),
          padding: material.EdgeInsets.symmetric(
            horizontal: context.scaled(QueryaDropdownTokens.menuItemPadding.horizontal),
            vertical: context.scaled(QueryaDropdownTokens.menuItemPadding.vertical),
          ),
          decoration: material.BoxDecoration(
            color: bg,
            borderRadius: material.BorderRadius.circular(radius),
          ),
          child: material.Row(
            children: [
              material.SizedBox(width: slot, child: _leading(context, cs)),
              material.SizedBox(width: context.scaled(6)),
              material.Expanded(
                child: material.Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: QueryaDropdownTokens.menuItemTextStyle(
                    context,
                    cs.popoverForeground,
                    selected: widget.selected,
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
