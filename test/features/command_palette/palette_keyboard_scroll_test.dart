import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/features/command_palette/command_palette_dialog.dart';
import 'package:querya_desktop/features/command_palette/quick_switcher_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

/// Scroll position of the result list of the open dialog.
double _listOffset(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

Future<void> _openDialog(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    queryaThemeTestShell(
      child: QueryaMotionScope(
        level: QueryaMotionLevel.full,
        child: Builder(
          builder: (context) {
            return Center(
              child: Button.primary(
                onPressed: () => open(context),
                child: const Text('Open dialog'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }
}

void main() {
  group('Command palette keeps the selected row in view (#1369)', () {
    final registry = QueryaCommandRegistry.instance;

    setUp(registry.resetForTest);
    tearDown(registry.resetForTest);

    testWidgets('Arrow Down past the viewport scrolls, Arrow Up scrolls back',
        (tester) async {
      registry.ensureCoreDefaults();
      for (var i = 0; i < 40; i++) {
        registry.register(
          QueryaCommand(
            id: 'test.command_$i',
            title: 'Scroll test command $i',
            execute: (_) {},
          ),
        );
      }
      await _openDialog(tester, showCommandPalette);

      expect(_listOffset(tester), 0);

      await _press(tester, LogicalKeyboardKey.arrowDown, 20);
      expect(_listOffset(tester), greaterThan(0));

      await _press(tester, LogicalKeyboardKey.arrowUp, 20);
      expect(_listOffset(tester), 0);
    });

    testWidgets('typing resets the list to the top', (tester) async {
      registry.ensureCoreDefaults();
      for (var i = 0; i < 40; i++) {
        registry.register(
          QueryaCommand(
            id: 'test.command_$i',
            title: 'Scroll test command $i',
            execute: (_) {},
          ),
        );
      }
      await _openDialog(tester, showCommandPalette);

      await _press(tester, LogicalKeyboardKey.arrowDown, 20);
      expect(_listOffset(tester), greaterThan(0));

      await tester.enterText(find.byType(TextField), 'Scroll test');
      await tester.pump();
      await tester.pump();

      expect(_listOffset(tester), 0);
    });
  });

  group('Quick switcher keeps the selected row in view (#1369)', () {
    final seed = [
      for (var i = 0; i < 40; i++)
        QueryaSchemaObject.postgres(
          database: 'app',
          schema: 'public',
          name: 'table_${i.toString().padLeft(2, '0')}',
          kind: QueryaSchemaObjectKind.table,
        ),
    ];

    testWidgets('Arrow Down past the viewport scrolls, Arrow Up scrolls back',
        (tester) async {
      await _openDialog(
        tester,
        (context) => showQuickSwitcher(context, seed: seed),
      );

      expect(_listOffset(tester), 0);

      await _press(tester, LogicalKeyboardKey.arrowDown, 20);
      expect(_listOffset(tester), greaterThan(0));

      await _press(tester, LogicalKeyboardKey.arrowUp, 20);
      expect(_listOffset(tester), 0);
    });
  });
}
