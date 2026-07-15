import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/connections/driver_manager_dialog.dart';
import 'package:querya_desktop/features/settings/preferences_dialog.dart';
import 'package:querya_desktop/features/extensions/presentation/pages/extension_manager_dialog.dart';
import 'package:querya_desktop/features/help/about_dialog.dart';
import 'package:querya_desktop/features/updater/update_available_badge.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/features/updater/update_dialog.dart';
import 'package:querya_desktop/core/actions/sql_editor_actions.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Custom bitsdojo title bar styled from [QueryaThemeScope] workbench tokens.
class QueryaWindowTitleBar extends StatelessWidget {
  const QueryaWindowTitleBar({
    super.key,
    required this.onNewDatabaseConnection,
    required this.onNewDatabaseConnectionFromUrl,
    this.activeConnection,
    this.onConnect,
    this.onReconnect,
    this.onDisconnect,
    this.onDisconnectAll,
    this.onDisconnectOthers,
    this.isReadOnly = false,
    this.onReadOnlyChanged,
  });

  final Future<void> Function() onNewDatabaseConnection;
  final Future<void> Function() onNewDatabaseConnectionFromUrl;
  final ConnectionRow? activeConnection;
  final VoidCallback? onConnect;
  final VoidCallback? onReconnect;
  final VoidCallback? onDisconnect;
  final VoidCallback? onDisconnectAll;
  final VoidCallback? onDisconnectOthers;
  final bool isReadOnly;
  final VoidCallback? onReadOnlyChanged;

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
                      material.Icons.storage_rounded,
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
                                    FocusManager
                                            .instance.primaryFocus?.context ??
                                        ctx,
                                    const NewSqlIntent(),
                                  );
                                },
                                child: const Text('New')),
                            MenuButton(
                                onPressed: (ctx) {
                                  Actions.maybeInvoke(
                                    FocusManager
                                            .instance.primaryFocus?.context ??
                                        ctx,
                                    const OpenSqlIntent(),
                                  );
                                },
                                child: const Text('Open...')),
                            MenuButton(
                                onPressed: (ctx) {
                                  Actions.maybeInvoke(
                                    FocusManager
                                            .instance.primaryFocus?.context ??
                                        ctx,
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
                            const MenuDivider(),
                            MenuButton(
                              leading: const material.Icon(
                                material.Icons.extension_rounded,
                                size: 18,
                              ),
                              onPressed: (ctx) =>
                                  showExtensionManagerDialog(ctx),
                              child: const Text('Extensions…'),
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
                              onPressed: (_) =>
                                  onNewDatabaseConnectionFromUrl(),
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
                              enabled: activeConnection != null,
                              leading: const material.Icon(
                                  material.Icons.power_rounded,
                                  size: 18),
                              onPressed: (_) => onConnect?.call(),
                              child: const Text('Connect'),
                            ),
                            MenuButton(
                              enabled: activeConnection != null,
                              leading: const material.Icon(
                                  material.Icons.refresh_rounded,
                                  size: 18),
                              onPressed: (_) => onReconnect?.call(),
                              child: const Text('Invalidate/Reconnect'),
                            ),
                            MenuButton(
                              enabled: activeConnection != null,
                              leading: const material.Icon(
                                  material.Icons.power_off_rounded,
                                  size: 18),
                              onPressed: (_) => onDisconnect?.call(),
                              child: const Text('Disconnect'),
                            ),
                            MenuButton(
                                onPressed: (_) => onDisconnectAll?.call(),
                                child: const Text('Disconnect All')),
                            MenuButton(
                                enabled: activeConnection != null,
                                onPressed: (_) => onDisconnectOthers?.call(),
                                child: const Text('Disconnect Others')),
                            const MenuDivider(),
                            MenuButton(
                              enabled: activeConnection != null,
                              leading: const material.Icon(
                                  material.Icons.lock_outline_rounded,
                                  size: 18),
                              trailing: isReadOnly
                                  ? const material.Icon(
                                      material.Icons.check_rounded,
                                      size: 16)
                                  : null,
                              onPressed: (_) => onReadOnlyChanged?.call(),
                              child: const Text('Read-only'),
                            ),
                          ],
                          child: const Text('Connection'),
                        ),
                        MenuButton(
                          subMenu: [
                            MenuButton(
                                onPressed: (ctx) => showAboutDialog(ctx),
                                child: const Text('About')),
                            MenuButton(
                              onPressed: (ctx) => showUpdateDialog(ctx),
                              child: const Text('Check for Updates…'),
                            ),
                            MenuButton(
                                onPressed: (_) => openQueryaDocumentation(),
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
                if (activeConnection != null && isReadOnly)
                  const QueryaReadOnlyBadge(),
                UpdateAvailableBadge(controller: UpdateController.instance),
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

/// Persistent title-bar indicator for a read-only workspace.
class QueryaReadOnlyBadge extends StatelessWidget {
  const QueryaReadOnlyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final warning = context.workbench.warning;
    return material.Tooltip(
      message: 'Read-only mode',
      child: material.Semantics(
        label: 'Read-only mode',
        child: material.Container(
          key: const Key('title_bar_read_only_badge'),
          margin: const material.EdgeInsets.only(right: 8),
          padding: const material.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: material.BoxDecoration(
            color: warning.withValues(alpha: 0.14),
            borderRadius: material.BorderRadius.circular(6),
            border: material.Border.all(
              color: warning.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(
                material.Icons.lock_outline_rounded,
                size: 13,
                color: warning,
              ),
              const Gap(5),
              Text(
                'Read-only',
                style: material.TextStyle(
                  color: warning,
                  fontSize: 11,
                  fontWeight: material.FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
