import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material show Scaffold, Container, MainAxisSize, GestureDetector, MouseRegion, SystemMouseCursors, HitTestBehavior, Icons, Icon;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'connections_panel.dart';
import 'driver_manager_dialog.dart';
import 'new_connection_dialog.dart';
import 'workspace_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  double _leftPanelWidth = 260;

  /// Currently selected connection (null = no connection selected).
  ConnectionRow? _activeConnection;

  void _onConnectionSelected(ConnectionRow connection) {
    setState(() {
      _activeConnection = connection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.dark.colorScheme;
    return material.Scaffold(
      backgroundColor: theme.background,
      body: Theme(
        data: AppTheme.dark,
        child: WindowBorder(
          color: theme.border.withValues(alpha: 0.6),
          width: 1,
          child: Column(
            children: [
              _CustomTitleBar(theme: theme),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: _leftPanelWidth,
                      child: ConnectionsPanel(
                        onConnectionSelected: _onConnectionSelected,
                      ),
                    ),
                    _VerticalResizeHandle(
                      onDrag: (dx) {
                        setState(() {
                          _leftPanelWidth = (_leftPanelWidth + dx)
                              .clamp(_minLeftWidth, _maxLeftWidth);
                        });
                      },
                    ),
                    Expanded(
                      child: WorkspacePanel(
                        activeConnection: _activeConnection,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalResizeHandle extends StatelessWidget {
  const _VerticalResizeHandle({required this.onDrag});

  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.resizeColumn,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onHorizontalDragUpdate: (e) => onDrag(e.delta.dx),
        child: material.Container(
          width: 6,
          color: theme.border.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

class _CustomTitleBar extends StatefulWidget {
  const _CustomTitleBar({required this.theme});

  final ColorScheme theme;

  @override
  State<_CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<_CustomTitleBar> {
  @override
  Widget build(BuildContext context) {
    final c = widget.theme;
    final buttonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: c.muted.withValues(alpha: 0.5),
      mouseDown: c.muted.withValues(alpha: 0.7),
      iconMouseOver: c.foreground,
      iconMouseDown: c.foreground,
    );
    final closeButtonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: const Color(0xFFE53935),
      mouseDown: const Color(0xFFB71C1C),
      iconMouseOver: const Color(0xFFFFFFFF),
      iconMouseDown: const Color(0xFFFFFFFF),
    );

    return material.Container(
      height: 40,
      color: c.background,
      child: WindowTitleBarBox(
        child: Row(
          children: [
            Expanded(
              child: MoveWindow(
                child: Row(
                  children: [
                    material.Container(width: 16),
                    Text('Querya').semiBold().small(),
                    const Gap(24),
                    Menubar(
                      border: false,
                      popoverOffset: const Offset(0, 8),
                      children: [
                        MenuButton(
                          child: const Text('File'),
                          subMenu: [
                            MenuButton(child: const Text('New'), onPressed: (_) {}),
                            MenuButton(child: const Text('Open...'), onPressed: (_) {}),
                            MenuButton(child: const Text('Save'), onPressed: (_) {}),
                            const MenuDivider(),
                            MenuButton(child: const Text('Exit'), onPressed: (_) {}),
                          ],
                        ),
                        MenuButton(
                          child: const Text('Connection'),
                          subMenu: [
                            MenuButton(
                              leading: material.Icon(material.Icons.add_link_rounded, size: 18),
                              trailing: Text('Shift+Ctrl+N').xSmall().muted(),
                              onPressed: (ctx) async {
                                final type = await showNewConnectionDialog(ctx);
                                if (type != null) {
                                  // TODO: add connection (no folder)
                                }
                              },
                              child: const Text('New Database Connection'),
                            ),
                            MenuButton(
                              leading: material.Icon(material.Icons.link_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('New Connection from URL'),
                            ),
                            MenuButton(
                              leading: material.Icon(material.Icons.settings_rounded, size: 18),
                              onPressed: (ctx) => showDriverManagerDialog(ctx),
                              child: const Text('Driver Manager'),
                            ),
                            const MenuDivider(),
                            MenuButton(
                              enabled: false,
                              leading: material.Icon(material.Icons.power_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Connect'),
                            ),
                            MenuButton(
                              leading: material.Icon(material.Icons.refresh_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Invalidate/Reconnect'),
                            ),
                            MenuButton(
                              leading: material.Icon(material.Icons.power_off_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Disconnect'),
                            ),
                            MenuButton(child: const Text('Disconnect All'), onPressed: (_) {}),
                            MenuButton(child: const Text('Disconnect Others'), onPressed: (_) {}),
                            const MenuDivider(),
                            MenuButton(
                              leading: material.Icon(material.Icons.lock_outline_rounded, size: 18),
                              onPressed: (_) {},
                              child: const Text('Read-only'),
                            ),
                          ],
                        ),
                        MenuButton(
                          child: const Text('Help'),
                          subMenu: [
                            MenuButton(child: const Text('About'), onPressed: (_) {}),
                            MenuButton(child: const Text('Documentation'), onPressed: (_) {}),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                MinimizeWindowButton(colors: buttonColors),
                MaximizeWindowButton(colors: buttonColors),
                CloseWindowButton(colors: closeButtonColors),
              ],
            )
          ],
        ),
      ),
    );
  }
}
