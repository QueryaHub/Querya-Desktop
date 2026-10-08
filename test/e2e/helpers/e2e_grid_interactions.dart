import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';

/// Keyboard and pointer helpers shared by grid scenarios.
class E2eGrid {
  E2eGrid._();

  /// Sends [key] with optional modifiers, e.g. `shortcut(t, LogicalKeyboardKey.keyF, ctrl: true)`.
  static Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
  }) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 50));
  }

  static Future<void> find_(WidgetTester tester) =>
      shortcut(tester, LogicalKeyboardKey.keyF, ctrl: true);
  static Future<void> groupings(WidgetTester tester) =>
      shortcut(tester, LogicalKeyboardKey.keyG, ctrl: true);
  static Future<void> enter(WidgetTester tester) =>
      shortcut(tester, LogicalKeyboardKey.enter);
  static Future<void> escape(WidgetTester tester) =>
      shortcut(tester, LogicalKeyboardKey.escape);

  /// Clicks the cell whose text is [text].
  static Future<void> tapCell(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Double-clicks the cell showing [text] to start inline editing.
  static Future<void> doubleTapCell(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Types into the focused editor and commits with Enter.
  static Future<void> typeAndCommit(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(EditableText).last, value);
    await enter(tester);
  }

  /// Asserts the staging buffer holds exactly the given pending changes.
  static void expectStaged(
    DataGridStagingBuffer buffer, {
    int modifiedCells = 0,
    int inserted = 0,
    int deleted = 0,
  }) {
    expect(buffer.modifiedCellCount, modifiedCells, reason: 'modified cells');
    expect(buffer.insertedRowCount, inserted, reason: 'inserted rows');
    expect(buffer.deletedRowCount, deleted, reason: 'deleted rows');
    expect(buffer.isDirty, modifiedCells + inserted + deleted > 0);
  }
}
