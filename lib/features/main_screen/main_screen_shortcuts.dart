import 'package:flutter/services.dart';

/// A window-wide shortcut of the shell.
enum MainShortcut {
  runScript,
  runStatement,
  preferences,
  toggleSidebar,
  commandPalette,
  quickSwitcher,
  newConnection,
  newQuery,
  newQueryTab,
  closeQueryTab,
  nextQueryTab,
  prevQueryTab,
  openSql,
  saveSql,
  welcomeTour,
  goHome,
}

/// Which [MainShortcut] a key press is. Pure: the screen decides what to do.
///
/// A letter shortcut matches on the physical key, the logical key, or the
/// Russian-layout letter on the same key, so it works on both layouts.
abstract final class MainScreenShortcuts {
  static const _ruR = LogicalKeyboardKey(0x0000043a); // к
  static const _ruComma = LogicalKeyboardKey(0x00000431); // б
  static const _ruB = LogicalKeyboardKey(0x00000438); // и
  static const _ruP = [
    LogicalKeyboardKey(0x00000437), // з
    LogicalKeyboardKey(0x00000417), // З
  ];
  static const _ruK = [
    LogicalKeyboardKey(0x0000043b), // л
    LogicalKeyboardKey(0x0000041b), // Л
  ];
  static const _ruN = LogicalKeyboardKey(0x00000442); // т
  static const _ruT = LogicalKeyboardKey(0x00000435); // е
  static const _ruW = LogicalKeyboardKey(0x00000446); // ц
  static const _ruO = LogicalKeyboardKey(0x00000449); // щ
  static const _ruS = LogicalKeyboardKey(0x0000044b); // ы
  static const _ruH = LogicalKeyboardKey(0x00000440); // р

  /// [cmdOrCtrl] is Cmd or Ctrl on macOS and Ctrl elsewhere.
  static MainShortcut? resolve(
    KeyEvent event, {
    required bool cmdOrCtrl,
    required bool shift,
    required bool alt,
  }) {
    final physical = event.physicalKey;
    final logical = event.logicalKey;
    bool key(PhysicalKeyboardKey p, LogicalKeyboardKey l,
            [List<LogicalKeyboardKey> also = const []]) =>
        physical == p || logical == l || also.contains(logical);

    final isEnter = physical == PhysicalKeyboardKey.enter ||
        physical == PhysicalKeyboardKey.numpadEnter ||
        logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter;
    final isF5 = key(PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5);
    final isKeyR = key(PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR, [_ruR]);

    // Execute, as in the editor: Ctrl/Cmd+Enter and Ctrl/Cmd+R run the
    // selection or the statement at the cursor; F5 and Ctrl/Cmd+Shift+Enter
    // run the whole script.
    if (isF5 || (cmdOrCtrl && shift && !alt && isEnter)) {
      return MainShortcut.runScript;
    }
    if (cmdOrCtrl && !shift && !alt && (isEnter || isKeyR)) {
      return MainShortcut.runStatement;
    }

    final plain = cmdOrCtrl && !shift && !alt;
    if (plain &&
        key(PhysicalKeyboardKey.comma, LogicalKeyboardKey.comma, [_ruComma])) {
      return MainShortcut.preferences;
    }
    if (plain && key(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB, [_ruB])) {
      return MainShortcut.toggleSidebar;
    }
    if (plain && key(PhysicalKeyboardKey.keyP, LogicalKeyboardKey.keyP, _ruP)) {
      return MainShortcut.commandPalette;
    }
    if (plain && key(PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK, _ruK)) {
      return MainShortcut.quickSwitcher;
    }
    if (cmdOrCtrl &&
        !alt &&
        key(PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN, [_ruN])) {
      return shift ? MainShortcut.newQuery : MainShortcut.newConnection;
    }
    if (plain && key(PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT, [_ruT])) {
      return MainShortcut.newQueryTab;
    }
    if (plain && key(PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW, [_ruW])) {
      return MainShortcut.closeQueryTab;
    }
    if (cmdOrCtrl &&
        !alt &&
        key(PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab)) {
      return shift ? MainShortcut.prevQueryTab : MainShortcut.nextQueryTab;
    }
    if (plain && key(PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO, [_ruO])) {
      return MainShortcut.openSql;
    }
    if (plain && key(PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS, [_ruS])) {
      return MainShortcut.saveSql;
    }
    // F1, or Ctrl/Cmd+Shift+H.
    if (key(PhysicalKeyboardKey.f1, LogicalKeyboardKey.f1) ||
        (cmdOrCtrl &&
            shift &&
            key(PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH, [_ruH]))) {
      return MainShortcut.welcomeTour;
    }
    if (cmdOrCtrl &&
        shift &&
        (physical == PhysicalKeyboardKey.digit0 ||
            physical == PhysicalKeyboardKey.numpad0 ||
            logical == LogicalKeyboardKey.digit0 ||
            logical == LogicalKeyboardKey.numpad0)) {
      return MainShortcut.goHome;
    }
    return null;
  }
}
