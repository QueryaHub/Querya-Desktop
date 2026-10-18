import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_divider.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_menu_surface.dart';

/// One command or submenu row on the kit's menu surface (#1732).
///
/// Replaces shadcn's `MenuButton` / `MenuItem`. When [subMenu] is non-empty,
/// renders a [material.SubmenuButton]; otherwise a [material.MenuItemButton].
class QueryaMenuItem extends material.StatelessWidget {
  const QueryaMenuItem({
    super.key,
    required this.child,
    this.leading,
    this.trailing,
    this.onPressed,
    this.onTap,
    this.subMenu,
    this.enabled = true,
  });

  /// The label or widget for this menu entry.
  final material.Widget child;

  /// Optional leading icon or decoration.
  final material.Widget? leading;

  /// Optional trailing widget, such as a keyboard shortcut hint or tag.
  final material.Widget? trailing;

  /// Callback called with [BuildContext] when activated.
  final void Function(material.BuildContext context)? onPressed;

  /// Parameterless callback called when activated.
  final material.VoidCallback? onTap;

  /// Submenu items shown when this item expands.
  final List<material.Widget>? subMenu;

  /// Whether this item is interactive. Defaults to true.
  final bool enabled;

  @override
  material.Widget build(material.BuildContext context) {
    if (subMenu != null && subMenu!.isNotEmpty) {
      return material.SubmenuButton(
        menuStyle: queryaMenuStyle(context),
        style: queryaMenuItemButtonStyle(context, enabled: enabled),
        leadingIcon: leading,
        trailingIcon: trailing,
        menuChildren: subMenu!,
        child: child,
      );
    }
    return material.MenuItemButton(
      style: queryaMenuItemButtonStyle(context, enabled: enabled),
      leadingIcon: leading,
      trailingIcon: trailing,
      onPressed: (enabled && (onPressed != null || onTap != null))
          ? () {
              onTap?.call();
              onPressed?.call(context);
            }
          : null,
      child: child,
    );
  }
}

/// Thin separator between sections in a menu (#1732).
///
/// Replaces shadcn's `MenuDivider`.
class QueryaMenuDivider extends material.StatelessWidget {
  const QueryaMenuDivider({super.key});

  @override
  material.Widget build(material.BuildContext context) {
    return const material.Padding(
      padding: material.EdgeInsets.symmetric(vertical: 4),
      child: QueryaDivider(),
    );
  }
}

/// Style for menu row buttons in popovers and context menus.
material.ButtonStyle queryaMenuItemButtonStyle(
  material.BuildContext context, {
  bool enabled = true,
}) {
  final cs = context.colors;
  final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);
  return material.MenuItemButton.styleFrom(
    minimumSize: material.Size(
      0,
      QueryaDropdownTokens.scaledMenuItemHeight(context),
    ),
    padding: material.EdgeInsets.symmetric(
      horizontal: context.scaled(8),
    ),
    foregroundColor: enabled ? cs.popoverForeground : cs.mutedForeground,
    disabledForegroundColor: cs.mutedForeground,
    iconColor: cs.mutedForeground,
    disabledIconColor: cs.mutedForeground,
    overlayColor: cs.accent.withValues(alpha: 0.14),
    shape: material.RoundedRectangleBorder(
      borderRadius: material.BorderRadius.circular(radius),
    ),
    textStyle: QueryaDropdownTokens.menuItemTextStyle(
      context,
      enabled ? cs.popoverForeground : cs.mutedForeground,
      selected: false,
    ),
  );
}

/// Wraps [child] to open a context menu on secondary click (right click),
/// long-press, or context-menu keyboard shortcut (#1732).
///
/// Replaces shadcn's `ContextMenu`. Supports eager [items] or lazy [itemsBuilder].
class QueryaContextMenu extends material.StatefulWidget {
  const QueryaContextMenu({
    super.key,
    required this.child,
    this.items,
    this.itemsBuilder,
    this.enabled = true,
    this.behavior = material.HitTestBehavior.translucent,
  }) : assert(
          items != null || itemsBuilder != null,
          'QueryaContextMenu requires either items or itemsBuilder',
        );

  final material.Widget child;
  final List<material.Widget>? items;
  final List<material.Widget> Function(material.BuildContext context)?
      itemsBuilder;
  final bool enabled;
  final material.HitTestBehavior behavior;

  @override
  material.State<QueryaContextMenu> createState() => _QueryaContextMenuState();
}

class _QueryaContextMenuState extends material.State<QueryaContextMenu> {
  final material.MenuController _controller = material.MenuController();
  bool _isOpen = false;

  void _open(material.Offset localPosition) {
    if (!widget.enabled) return;
    if (widget.itemsBuilder != null) {
      setState(() {
        _isOpen = true;
      });
    }
    _controller.open(position: localPosition);
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (!widget.enabled) return widget.child;

    final children = widget.items != null
        ? widget.items!
        : (_isOpen ? widget.itemsBuilder!(context) : const <material.Widget>[]);

    return material.MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      style: queryaMenuStyle(context),
      onClose: () {
        if (_isOpen) {
          setState(() {
            _isOpen = false;
          });
        }
      },
      menuChildren: children,
      builder: (context, controller, child) {
        return material.Shortcuts(
          shortcuts: const <material.ShortcutActivator, material.Intent>{
            material.SingleActivator(LogicalKeyboardKey.contextMenu):
                _OpenContextMenuIntent(),
            material.SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _OpenContextMenuIntent(),
          },
          child: material.Actions(
            actions: <Type, material.Action<material.Intent>>{
              _OpenContextMenuIntent:
                  material.CallbackAction<_OpenContextMenuIntent>(
                onInvoke: (_) {
                  final box = context.findRenderObject() as material.RenderBox?;
                  final pos = box != null
                      ? box.size.center(material.Offset.zero)
                      : material.Offset.zero;
                  _open(pos);
                  return null;
                },
              ),
            },
            child: material.GestureDetector(
              behavior: widget.behavior,
              onSecondaryTapDown: (details) => _open(details.localPosition),
              onLongPressStart: (details) => _open(details.localPosition),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _OpenContextMenuIntent extends material.Intent {
  const _OpenContextMenuIntent();
}

/// Shows a context menu at [position] with the given [items].
Future<void> showQueryaContextMenu({
  required material.BuildContext context,
  required material.Offset position,
  required List<material.Widget> items,
}) async {
  final overlay = material.Overlay.of(context, rootOverlay: true);
  late final material.OverlayEntry entry;
  var removed = false;

  void safeRemove() {
    if (!removed && entry.mounted) {
      removed = true;
      entry.remove();
    }
  }

  entry = material.OverlayEntry(
    builder: (overlayContext) {
      return _StandaloneContextMenuOverlay(
        position: position,
        items: items,
        onClose: safeRemove,
      );
    },
  );

  overlay.insert(entry);
}

/// Shows a context menu at [position] with lazily evaluated [itemsBuilder].
Future<void> showQueryaContextMenuBuilder({
  required material.BuildContext context,
  required material.Offset position,
  required List<material.Widget> Function(material.BuildContext context)
      itemsBuilder,
}) {
  return showQueryaContextMenu(
    context: context,
    position: position,
    items: itemsBuilder(context),
  );
}

class _StandaloneContextMenuOverlay extends material.StatefulWidget {
  const _StandaloneContextMenuOverlay({
    required this.position,
    required this.items,
    required this.onClose,
  });

  final material.Offset position;
  final List<material.Widget> items;
  final material.VoidCallback onClose;

  @override
  material.State<_StandaloneContextMenuOverlay> createState() =>
      _StandaloneContextMenuOverlayState();
}

class _StandaloneContextMenuOverlayState
    extends material.State<_StandaloneContextMenuOverlay> {
  final material.MenuController _controller = material.MenuController();
  final material.FocusNode _overlayFocus =
      material.FocusNode(debugLabel: 'StandaloneContextMenu');

  @override
  void initState() {
    super.initState();
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.open(position: widget.position);
        _overlayFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _overlayFocus.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Shortcuts(
      shortcuts: const <material.ShortcutActivator, material.Intent>{
        material.SingleActivator(LogicalKeyboardKey.escape):
            material.DismissIntent(),
      },
      child: material.Actions(
        actions: <Type, material.Action<material.Intent>>{
          material.DismissIntent:
              material.CallbackAction<material.DismissIntent>(
            onInvoke: (_) {
              _controller.close();
              widget.onClose();
              return null;
            },
          ),
        },
        child: material.Focus(
          focusNode: _overlayFocus,
          autofocus: true,
          child: material.Stack(
            children: [
              material.Positioned.fill(
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.translucent,
                  onTapDown: (_) {
                    _controller.close();
                    widget.onClose();
                  },
                  onSecondaryTapDown: (_) {
                    _controller.close();
                    widget.onClose();
                  },
                  child: const material.SizedBox.expand(),
                ),
              ),
              material.Positioned(
                left: 0,
                top: 0,
                child: material.FocusScope(
                  autofocus: true,
                  child: material.MenuAnchor(
                    controller: _controller,
                    consumeOutsideTap: true,
                    style: queryaMenuStyle(context),
                    onClose: widget.onClose,
                    menuChildren: widget.items,
                    child: const material.SizedBox.shrink(),
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
