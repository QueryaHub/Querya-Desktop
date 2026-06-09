import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
/// Styling uses shadcn [ColorScheme] tokens from [Theme.of].
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
    this.alignmentOffset = const material.Offset(0, 6),
    this.menuMaxHeight = 320,
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

  material.Widget _triggerLabel({
    required String label,
    required ColorScheme cs,
    required bool expand,
  }) {
    final text = material.Text(
      label,
      maxLines: 1,
      overflow: material.TextOverflow.ellipsis,
      style: material.TextStyle(
        fontSize: 14,
        color: widget.enabled ? cs.popoverForeground : cs.mutedForeground,
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
    final selected = item.value == widget.value;
    return material.MenuItemButton(
      style: material.MenuItemButton.styleFrom(
        minimumSize: const material.Size(180, 36),
        padding: const material.EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: selected ? cs.muted.withValues(alpha: 0.45) : null,
        foregroundColor: cs.popoverForeground,
        disabledForegroundColor: cs.mutedForeground.withValues(alpha: 0.5),
        shape: material.RoundedRectangleBorder(
          borderRadius: material.BorderRadius.circular(6),
        ),
      ),
      onPressed: !widget.enabled || !item.enabled
          ? null
          : () {
              widget.onSelected(item.value);
              _controller.close();
            },
      leadingIcon: item.leading,
      child: material.Text(
        item.label,
        style: material.TextStyle(
          fontSize: 14,
          fontWeight: selected ? material.FontWeight.w600 : material.FontWeight.w400,
        ),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusMd;
    final label = _labelFor(widget.value);
    final fieldWidth = widget.expandToParent ? null : widget.width;

    final menuChildren = widget.items.map((item) => _menuItem(item, cs)).toList();

    final anchor = material.MenuAnchor(
      controller: _controller,
      alignmentOffset: widget.alignmentOffset,
      consumeOutsideTap: true,
      style: material.MenuStyle(
        backgroundColor: material.WidgetStatePropertyAll(cs.popover),
        surfaceTintColor: material.WidgetStatePropertyAll(cs.popover),
        elevation: const material.WidgetStatePropertyAll(8),
        maximumSize: material.WidgetStatePropertyAll(
          material.Size(double.infinity, widget.menuMaxHeight),
        ),
        padding: const material.WidgetStatePropertyAll(
          material.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
        final field = material.InkWell(
          onTap: widget.enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          borderRadius: material.BorderRadius.circular(6),
          child: material.Container(
            width: fieldWidth,
            padding: const material.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: material.BoxDecoration(
              border: material.Border(
                bottom: material.BorderSide(
                  color: widget.enabled ? cs.border : cs.border.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: material.Row(
              mainAxisSize:
                  widget.expandToParent ? material.MainAxisSize.max : material.MainAxisSize.min,
              children: [
                _triggerLabel(
                  label: label,
                  cs: cs,
                  expand: widget.expandToParent,
                ),
                material.Icon(
                  material.Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: widget.enabled ? cs.mutedForeground : cs.mutedForeground.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        );

        if (widget.expandToParent) {
          return material.SizedBox(width: double.infinity, child: field);
        }
        return field;
      },
    );

    if (fieldWidth != null && !widget.expandToParent) {
      return material.SizedBox(width: fieldWidth, child: anchor);
    }
    return anchor;
  }
}
