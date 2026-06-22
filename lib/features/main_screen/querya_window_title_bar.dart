import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material
    show BuildContext, Container, Icon, Icons, MainAxisSize, Widget;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/connections/driver_manager_dialog.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Custom bitsdojo title bar styled from [QueryaThemeScope] workbench tokens.
class QueryaWindowTitleBar extends StatelessWidget {
  const QueryaWindowTitleBar({
    super.key,
    required this.onNewDatabaseConnection,
  });

  final Future<void> Function() onNewDatabaseConnection;

  @visibleForTesting
  static Color titleBarBackground(BuildContext context) =>
      context.workbench.canvas;

  @visibleForTesting
  static WindowButtonColors windowButtonColors(BuildContext context) {
    final wb = context.workbench;
    final cs = Theme.of(context).colorScheme;
    return WindowButtonColors(
      iconNormal: wb.mutedForeground,
      mouseOver: wb.surface.withValues(alpha: 0.85),
      mouseDown: wb.borderSubtle.withValues(alpha: 0.55),
      iconMouseOver: cs.foreground,
      iconMouseDown: cs.foreground,
    );
  }

  @visibleForTesting
  static WindowButtonColors closeButtonColors(BuildContext context) {
    final wb = context.workbench;
    return WindowButtonColors(
      iconNormal: wb.mutedForeground,
      mouseOver: wb.destructive,
      mouseDown: wb.destructive.withValues(alpha: 0.85),
      iconMouseOver: wb.onAccent,
      iconMouseDown: wb.onAccent,
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final buttonColors = windowButtonColors(context);
    final closeButtonColors = QueryaWindowTitleBar.closeButtonColors(context);

    return material.Container(
      height: 40,
      color: titleBarBackground(context),
      child: WindowTitleBarBox(
        child: Row(
          children: [
            Expanded(
              child: MoveWindow(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    material.Icon(
                      material.Icons.search_rounded,
                      size: 18,
                      color: wb.accent,
                    ),
                    const Gap(8),
                    const Text('Querya').semiBold().small(),
                    const Gap(24),
                    Menubar(
                      border: false,
                      popoverOffset: const Offset(0, 8),
                      children: [
                        MenuButton(
                          subMenu: [
                            MenuButton(
                                onPressed: (ctx) {
                                  Actions.maybeInvoke(
                                    FocusManager.instance.primaryFocus?.context ?? ctx,
                                    const NewSqlIntent(),
                                  );
                                },
                                child: const Text('New')),
                            MenuButton(
                                onPressed: (ctx) {
                                  Actions.maybeInvoke(
                                    FocusManager.instance.primaryFocus?.context ?? ctx,
                                    const OpenSqlIntent(),
                                  );
                                },
                                child: const Text('Open...')),
                            MenuButton(
                                onPressed: (ctx) {
                                  Actions.maybeInvoke(
                                    FocusManager.instance.primaryFocus?.context ?? ctx,
                                    const SaveSqlIntent(),
                                  );
                                },
                                child: const Text('Save')),
                            const MenuDivider(),
                            MenuButton(
                                onPressed: (_) => appWindow.close(),
                                child: const Text('Exit')),
                          ],
                          child: const Text('File'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(
                              leading: const material.Icon(
                                material.Icons.tune_rounded,
                                size: 18,
                              ),
                              onPressed: (ctx) => showPreferencesDialog(ctx),
                              child: const Text('Preferences…'),
                            ),
                          ],
                          child: const Text('Edit'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.add_link_rounded,
                                  size: 18),
                              trailing:
                                  const Text('Shift+Ctrl+N').xSmall().muted(),
                              onPressed: (_) => onNewDatabaseConnection(),
                              child: const Text('New Database Connection'),
                            ),
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.link_rounded,
                                  size: 18),
                              onPressed: (_) {},
                              child: const Text('New Connection from URL'),
                            ),
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.settings_rounded,
                                  size: 18),
                              onPressed: (ctx) => showDriverManagerDialog(ctx),
                              child: const Text('Driver Manager'),
                            ),
                            const MenuDivider(),
                            MenuButton(
                              enabled: false,
                              leading: const material.Icon(
                                  material.Icons.power_rounded,
                                  size: 18),
                              onPressed: (_) {},
                              child: const Text('Connect'),
                            ),
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.refresh_rounded,
                                  size: 18),
                              onPressed: (_) {},
                              child: const Text('Invalidate/Reconnect'),
                            ),
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.power_off_rounded,
                                  size: 18),
                              onPressed: (_) {},
                              child: const Text('Disconnect'),
                            ),
                            MenuButton(
                                onPressed: (_) {},
                                child: const Text('Disconnect All')),
                            MenuButton(
                                onPressed: (_) {},
                                child: const Text('Disconnect Others')),
                            const MenuDivider(),
                            MenuButton(
                              leading: const material.Icon(
                                  material.Icons.lock_outline_rounded,
                                  size: 18),
                              onPressed: (_) {},
                              child: const Text('Read-only'),
                            ),
                          ],
                          child: const Text('Connection'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(
                                onPressed: (_) {}, child: const Text('About')),
                            MenuButton(
                                onPressed: (_) {},
                                child: const Text('Documentation')),
                          ],
                          child: const Text('Help'),
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
