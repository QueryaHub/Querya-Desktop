import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/main_screen_shortcuts.dart';

KeyEvent _down(PhysicalKeyboardKey p, LogicalKeyboardKey l) =>
    KeyDownEvent(physicalKey: p, logicalKey: l, timeStamp: Duration.zero);

MainShortcut? _resolve(
  PhysicalKeyboardKey p,
  LogicalKeyboardKey l, {
  bool cmd = true,
  bool shift = false,
  bool alt = false,
}) =>
    MainScreenShortcuts.resolve(_down(p, l),
        cmdOrCtrl: cmd, shift: shift, alt: alt);

void main() {
  group('Ctrl/Cmd letters', () {
    final cases = <(String, PhysicalKeyboardKey, LogicalKeyboardKey,
        MainShortcut)>[
      ('B', PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB,
          MainShortcut.toggleSidebar),
      ('P', PhysicalKeyboardKey.keyP, LogicalKeyboardKey.keyP,
          MainShortcut.commandPalette),
      ('K', PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK,
          MainShortcut.quickSwitcher),
      ('T', PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT,
          MainShortcut.newQueryTab),
      ('W', PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW,
          MainShortcut.closeQueryTab),
      ('O', PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO,
          MainShortcut.openSql),
      ('S', PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS,
          MainShortcut.saveSql),
      (',', PhysicalKeyboardKey.comma, LogicalKeyboardKey.comma,
          MainShortcut.preferences),
      ('R', PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR,
          MainShortcut.runStatement),
      ('Enter', PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter,
          MainShortcut.runStatement),
    ];
    for (final (name, p, l, shortcut) in cases) {
      test('Ctrl+$name is $shortcut', () {
        expect(_resolve(p, l), shortcut);
      });
      test('Ctrl+Alt+$name and a bare $name are not shortcuts', () {
        expect(_resolve(p, l, alt: true), isNull);
        expect(_resolve(p, l, cmd: false), isNull);
      });
    }
  });

  test('Ctrl+N is a new connection, Ctrl+Shift+N a new query', () {
    expect(_resolve(PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN),
        MainShortcut.newConnection);
    expect(
        _resolve(PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN,
            shift: true),
        MainShortcut.newQuery);
  });

  test('Ctrl+Tab goes forward, Ctrl+Shift+Tab back', () {
    expect(_resolve(PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab),
        MainShortcut.nextQueryTab);
    expect(
        _resolve(PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab, shift: true),
        MainShortcut.prevQueryTab);
  });

  test('F5 and Ctrl+Shift+Enter run the script, with or without Ctrl', () {
    expect(_resolve(PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5, cmd: false),
        MainShortcut.runScript);
    expect(
        _resolve(PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter,
            shift: true),
        MainShortcut.runScript);
    expect(
        _resolve(PhysicalKeyboardKey.numpadEnter, LogicalKeyboardKey.numpadEnter,
            shift: true),
        MainShortcut.runScript);
  });

  test('F1 and Ctrl+Shift+H open the tour; Ctrl+Shift+0 goes home', () {
    expect(_resolve(PhysicalKeyboardKey.f1, LogicalKeyboardKey.f1, cmd: false),
        MainShortcut.welcomeTour);
    expect(
        _resolve(PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH,
            shift: true),
        MainShortcut.welcomeTour);
    expect(
        _resolve(PhysicalKeyboardKey.digit0, LogicalKeyboardKey.digit0,
            shift: true),
        MainShortcut.goHome);
    expect(_resolve(PhysicalKeyboardKey.digit0, LogicalKeyboardKey.digit0),
        isNull);
  });

  test('a Russian layout reaches the same shortcuts', () {
    // The physical key is whatever the layout sends; the logical one is the
    // Cyrillic letter.
    final ru = <(int, MainShortcut)>[
      (0x0000043a, MainShortcut.runStatement), // к
      (0x00000431, MainShortcut.preferences), // б
      (0x00000438, MainShortcut.toggleSidebar), // и
      (0x00000437, MainShortcut.commandPalette), // з
      (0x00000417, MainShortcut.commandPalette), // З
      (0x0000043b, MainShortcut.quickSwitcher), // л
      (0x0000041b, MainShortcut.quickSwitcher), // Л
      (0x00000435, MainShortcut.newQueryTab), // е
      (0x00000446, MainShortcut.closeQueryTab), // ц
      (0x00000449, MainShortcut.openSql), // щ
      (0x0000044b, MainShortcut.saveSql), // ы
    ];
    for (final (code, shortcut) in ru) {
      expect(_resolve(PhysicalKeyboardKey.abort, LogicalKeyboardKey(code)),
          shortcut,
          reason: code.toRadixString(16));
    }
    expect(
        _resolve(PhysicalKeyboardKey.abort, const LogicalKeyboardKey(0x00000442)),
        MainShortcut.newConnection); // т
  });

  test('other keys are not shortcuts', () {
    expect(_resolve(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA), isNull);
    expect(_resolve(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape),
        isNull);
  });
}
