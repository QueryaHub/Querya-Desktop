import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/preferences_dialog.dart';

/// Native macOS top menu bar integration via Flutter's [PlatformMenuBar].
///
/// Configures system-level application, file, edit, view, window, and help menus
/// with macOS-standard keyboard shortcuts (Command / Meta modifier).
class QueryaPlatformMenuBar extends StatelessWidget {
  const QueryaPlatformMenuBar({
    super.key,
    required this.child,
    this.onNewConnection,
    this.onNewQueryTab,
    this.onOpenSqlScript,
    this.onSaveQuery,
    this.onExecuteQuery,
    this.onCloseTab,
    this.onToggleSidebar,
    this.onOpenPreferences,
    this.onOpenWelcomeTour,
    this.onGoHome,
    this.onFocusFilterBar,
    this.onToggleGroupings,
  });

  final Widget child;
  final VoidCallback? onNewConnection;
  final VoidCallback? onNewQueryTab;
  final VoidCallback? onOpenSqlScript;
  final VoidCallback? onSaveQuery;
  final VoidCallback? onExecuteQuery;
  final VoidCallback? onCloseTab;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onOpenPreferences;
  final VoidCallback? onOpenWelcomeTour;
  final VoidCallback? onGoHome;
  final VoidCallback? onFocusFilterBar;
  final VoidCallback? onToggleGroupings;

  static const String repoUrl = 'https://github.com/QueryaHub/Querya-Desktop';
  static const String issuesUrl =
      'https://github.com/QueryaHub/Querya-Desktop/issues/new';

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        // 1. Application Menu (macOS App Name)
        PlatformMenu(
          label: 'Querya',
          menus: [
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.about))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about)
            else
              PlatformMenuItem(
                label: 'About Querya',
                onSelected: onOpenWelcomeTour,
              ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Preferences...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onOpenPreferences ??
                      () => showPreferencesDialog(context),
                ),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.hide))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.hideOtherApplications))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.showAllApplications))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.quit))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit),
          ],
        ),

        // 2. File Menu
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Connection...',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: onNewConnection,
            ),
            PlatformMenuItem(
              label: 'New Query Tab',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
              ),
              onSelected: onNewQueryTab,
            ),
            PlatformMenuItem(
              label: 'Open SQL Script...',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: onOpenSqlScript,
            ),
            PlatformMenuItem(
              label: 'Save Query',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
              onSelected: onSaveQuery,
            ),
            if (onExecuteQuery != null)
              PlatformMenuItem(
                label: 'Run Query / Script',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.enter,
                  meta: true,
                ),
                onSelected: onExecuteQuery,
              ),
            if (onCloseTab != null)
              PlatformMenuItem(
                label: 'Close Tab',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                ),
                onSelected: onCloseTab,
              ),
          ],
        ),

        // 3. Edit Menu
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(
              label: 'Undo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: () {
                final focusCtx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(
                  focusCtx,
                  const UndoTextIntent(SelectionChangedCause.keyboard),
                );
              },
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () {
                final focusCtx =
                    FocusManager.instance.primaryFocus?.context ?? context;
                Actions.maybeInvoke(
                  focusCtx,
                  const RedoTextIntent(SelectionChangedCause.keyboard),
                );
              },
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () {
                    final focusCtx =
                        FocusManager.instance.primaryFocus?.context ?? context;
                    Actions.maybeInvoke(
                      focusCtx,
                      const CopySelectionTextIntent.cut(
                          SelectionChangedCause.keyboard),
                    );
                  },
                ),
                const PlatformMenuItem(
                  label: 'Copy',
                  shortcut: SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () {
                    final focusCtx =
                        FocusManager.instance.primaryFocus?.context ?? context;
                    Actions.maybeInvoke(
                      focusCtx,
                      const PasteTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () {
                    final focusCtx =
                        FocusManager.instance.primaryFocus?.context ?? context;
                    Actions.maybeInvoke(
                      focusCtx,
                      const SelectAllTextIntent(SelectionChangedCause.keyboard),
                    );
                  },
                ),
              ],
            ),
          ],
        ),

        // 4. View Menu
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Toggle Sidebar',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: true,
              ),
              onSelected: onToggleSidebar,
            ),
            if (onFocusFilterBar != null)
              PlatformMenuItem(
                label: 'Compound Filter Bar',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  meta: true,
                ),
                onSelected: onFocusFilterBar,
              ),
            if (onToggleGroupings != null)
              PlatformMenuItem(
                label: 'Groupings & Pivot Drawer',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyG,
                  meta: true,
                ),
                onSelected: onToggleGroupings,
              ),
            PlatformMenuItem(
              label: 'Return to Start Screen',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit0,
                meta: true,
                shift: true,
              ),
              onSelected: onGoHome,
            ),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.toggleFullScreen))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen),
          ],
        ),

        // 5. Window Menu
        PlatformMenu(
          label: 'Window',
          menus: [
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.minimizeWindow))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.minimizeWindow),
            if (PlatformProvidedMenuItem.hasMenu(
                PlatformProvidedMenuItemType.zoomWindow))
              const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),

        // 6. Help Menu
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'Welcome Tour & Guide',
              shortcut: const SingleActivator(LogicalKeyboardKey.f1),
              onSelected: onOpenWelcomeTour,
            ),
            PlatformMenuItem(
              label: 'Keyboard Shortcuts Cheat Sheet',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyH,
                meta: true,
                shift: true,
              ),
              onSelected: onOpenWelcomeTour,
            ),
            PlatformMenuItem(
              label: 'Querya GitHub Repository',
              onSelected: () => unawaited(launchUrl(Uri.parse(repoUrl))),
            ),
            PlatformMenuItem(
              label: 'Report an Issue...',
              onSelected: () => unawaited(launchUrl(Uri.parse(issuesUrl))),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
