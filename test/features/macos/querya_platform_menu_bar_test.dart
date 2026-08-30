import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/macos/querya_platform_menu_bar.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueryaPlatformMenuBar', () {
    testWidgets('mounts PlatformMenuBar with standard macOS menu hierarchy',
        (tester) async {
      var newConnectionInvoked = false;
      var newQueryTabInvoked = false;
      var openSqlInvoked = false;
      var saveQueryInvoked = false;
      var executeQueryInvoked = false;
      var toggleSidebarInvoked = false;
      var preferencesInvoked = false;
      var tourInvoked = false;
      var goHomeInvoked = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaPlatformMenuBar(
              onNewConnection: () => newConnectionInvoked = true,
              onNewQueryTab: () => newQueryTabInvoked = true,
              onOpenSqlScript: () => openSqlInvoked = true,
              onSaveQuery: () => saveQueryInvoked = true,
              onExecuteQuery: () => executeQueryInvoked = true,
              onToggleSidebar: () => toggleSidebarInvoked = true,
              onOpenPreferences: () => preferencesInvoked = true,
              onOpenWelcomeTour: () => tourInvoked = true,
              onGoHome: () => goHomeInvoked = true,
              child: const material.Text('Main App Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main App Content'), findsOneWidget);

      final platformMenuBarFinder = find.byType(PlatformMenuBar);
      expect(platformMenuBarFinder, findsOneWidget);

      final platformMenuBar =
          tester.widget<PlatformMenuBar>(platformMenuBarFinder);
      expect(platformMenuBar.menus.length, 6);

      // 1. App Menu (Querya)
      final appMenu = platformMenuBar.menus[0] as PlatformMenu;
      expect(appMenu.label, 'Querya');

      // 2. File Menu
      final fileMenu = platformMenuBar.menus[1] as PlatformMenu;
      expect(fileMenu.label, 'File');
      final fileItems = fileMenu.menus.whereType<PlatformMenuItem>().toList();
      expect(fileItems.any((m) => m.label == 'New Connection...'), isTrue);
      expect(fileItems.any((m) => m.label == 'New Query Tab'), isTrue);
      expect(fileItems.any((m) => m.label == 'Open SQL Script...'), isTrue);
      expect(fileItems.any((m) => m.label == 'Save Query'), isTrue);
      expect(fileItems.any((m) => m.label == 'Run Query / Script'), isTrue);

      // 3. Edit Menu
      final editMenu = platformMenuBar.menus[2] as PlatformMenu;
      expect(editMenu.label, 'Edit');

      // 4. View Menu
      final viewMenu = platformMenuBar.menus[3] as PlatformMenu;
      expect(viewMenu.label, 'View');
      final viewItems = viewMenu.menus.whereType<PlatformMenuItem>().toList();
      expect(viewItems.any((m) => m.label == 'Toggle Sidebar'), isTrue);
      expect(viewItems.any((m) => m.label == 'Return to Start Screen'), isTrue);

      // 5. Window Menu
      final windowMenu = platformMenuBar.menus[4] as PlatformMenu;
      expect(windowMenu.label, 'Window');

      // 6. Help Menu
      final helpMenu = platformMenuBar.menus[5] as PlatformMenu;
      expect(helpMenu.label, 'Help');
      final helpItems = helpMenu.menus.whereType<PlatformMenuItem>().toList();
      expect(helpItems.any((m) => m.label == 'Welcome Tour & Guide'), isTrue);
      expect(helpItems.any((m) => m.label == 'Keyboard Shortcuts Cheat Sheet'),
          isTrue);

      // Invoke callbacks directly
      fileItems
          .firstWhere((m) => m.label == 'New Connection...')
          .onSelected
          ?.call();
      expect(newConnectionInvoked, isTrue);

      fileItems
          .firstWhere((m) => m.label == 'New Query Tab')
          .onSelected
          ?.call();
      expect(newQueryTabInvoked, isTrue);

      fileItems
          .firstWhere((m) => m.label == 'Open SQL Script...')
          .onSelected
          ?.call();
      expect(openSqlInvoked, isTrue);

      fileItems.firstWhere((m) => m.label == 'Save Query').onSelected?.call();
      expect(saveQueryInvoked, isTrue);

      fileItems
          .firstWhere((m) => m.label == 'Run Query / Script')
          .onSelected
          ?.call();
      expect(executeQueryInvoked, isTrue);

      viewItems
          .firstWhere((m) => m.label == 'Toggle Sidebar')
          .onSelected
          ?.call();
      expect(toggleSidebarInvoked, isTrue);

      viewItems
          .firstWhere((m) => m.label == 'Return to Start Screen')
          .onSelected
          ?.call();
      expect(goHomeInvoked, isTrue);

      helpItems
          .firstWhere((m) => m.label == 'Welcome Tour & Guide')
          .onSelected
          ?.call();
      expect(tourInvoked, isTrue);

      final prefGroup = appMenu.menus.whereType<PlatformMenuItemGroup>().first;
      final prefItem = prefGroup.members.whereType<PlatformMenuItem>().first;
      prefItem.onSelected?.call();
      expect(preferencesInvoked, isTrue);
    });

    testWidgets('shortcuts verify Command (meta: true) keybindings',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: QueryaPlatformMenuBar(
              child: material.Text('Shortcuts Test Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final platformMenuBar = tester.widget<PlatformMenuBar>(
        find.byType(PlatformMenuBar),
      );

      final fileMenu = platformMenuBar.menus[1] as PlatformMenu;
      final fileItems = fileMenu.menus.whereType<PlatformMenuItem>().toList();

      final newConnItem =
          fileItems.firstWhere((m) => m.label == 'New Connection...');
      expect(newConnItem.shortcut,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true));

      final newTabItem =
          fileItems.firstWhere((m) => m.label == 'New Query Tab');
      expect(
          newTabItem.shortcut,
          const SingleActivator(LogicalKeyboardKey.keyN,
              meta: true, shift: true));

      final openSqlItem =
          fileItems.firstWhere((m) => m.label == 'Open SQL Script...');
      expect(openSqlItem.shortcut,
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true));

      final saveQueryItem =
          fileItems.firstWhere((m) => m.label == 'Save Query');
      expect(saveQueryItem.shortcut,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true));

      final viewMenu = platformMenuBar.menus[3] as PlatformMenu;
      final viewItems = viewMenu.menus.whereType<PlatformMenuItem>().toList();
      final sidebarItem =
          viewItems.firstWhere((m) => m.label == 'Toggle Sidebar');
      expect(sidebarItem.shortcut,
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true));
    });
  });
}
