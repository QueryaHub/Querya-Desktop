import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_menu_surface.dart';

/// Top-level application menu bar for the window title bar (#1732).
///
/// Replaces shadcn's `Menubar`. Supports keyboard navigation: Alt / F10 focuses
/// the menu bar, arrow keys navigate between and inside menus, Esc dismisses.
class QueryaMenuBar extends material.StatefulWidget {
  const QueryaMenuBar({
    super.key,
    required this.children,
    this.controller,
  });

  /// The top-level menu triggers (typically [QueryaMenuItem] with [subMenu]).
  final List<material.Widget> children;

  /// Optional menu controller.
  final material.MenuController? controller;

  @override
  material.State<QueryaMenuBar> createState() => _QueryaMenuBarState();
}

class _QueryaMenuBarState extends material.State<QueryaMenuBar> {
  final material.FocusNode _focusNode =
      material.FocusNode(debugLabel: 'QueryaMenuBar');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Focus(
      focusNode: _focusNode,
      child: material.MenuBar(
        controller: widget.controller,
        style: const material.MenuStyle(
          backgroundColor:
              material.WidgetStatePropertyAll(material.Colors.transparent),
          surfaceTintColor:
              material.WidgetStatePropertyAll(material.Colors.transparent),
          shadowColor:
              material.WidgetStatePropertyAll(material.Colors.transparent),
          elevation: material.WidgetStatePropertyAll(0),
          padding: material.WidgetStatePropertyAll(material.EdgeInsets.zero),
        ),
        children: [
          for (final child in widget.children)
            _wrapTopLevelItem(context, child),
        ],
      ),
    );
  }

  material.Widget _wrapTopLevelItem(
    material.BuildContext context,
    material.Widget item,
  ) {
    if (item is QueryaMenuItem && item.subMenu != null) {
      final cs = context.colors;
      return material.SubmenuButton(
        key: item.key,
        menuStyle: queryaMenuStyle(context),
        style: material.SubmenuButton.styleFrom(
          padding:
              const material.EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          minimumSize: const material.Size(0, 26),
          foregroundColor: cs.foreground,
          overlayColor: cs.accent.withValues(alpha: 0.14),
          shape: material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(4),
          ),
          textStyle: const material.TextStyle(
            fontSize: 12,
            fontWeight: material.FontWeight.w500,
          ),
        ),
        leadingIcon: item.leading,
        trailingIcon: item.trailing,
        menuChildren: item.subMenu!,
        child: item.child,
      );
    }
    return item;
  }
}
