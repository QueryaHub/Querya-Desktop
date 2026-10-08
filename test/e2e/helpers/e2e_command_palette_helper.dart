import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the Command Palette (`Ctrl+P`) the way a user does.
class E2ePalette {
  E2ePalette._();

  static Future<void> open(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  static Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).last, query);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Selects the entry registered under [commandId] (e.g. `querya.theme.toggle`).
  static Future<void> select(WidgetTester tester, String commandId) async {
    await tester.tap(find.byKey(ValueKey(commandId)));
    await tester.pump(const Duration(milliseconds: 150));
  }

  /// Opens the palette, filters by [query] and runs [commandId].
  static Future<void> run(
    WidgetTester tester,
    String query,
    String commandId,
  ) async {
    await open(tester);
    await search(tester, query);
    await select(tester, commandId);
  }

  static Finder get field => find.text('Type a command…');
}
