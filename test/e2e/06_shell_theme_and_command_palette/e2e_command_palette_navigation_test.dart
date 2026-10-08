import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode, ValueKey;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';

import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_command_palette_helper.dart';
import '../helpers/e2e_grid_interactions.dart';

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_palette_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  Future<void> closeDialog(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await E2eAppHarness.settle(tester);
    }
  }

  testWidgets('palette command toggles the theme mode', (tester) async {
    final controller = ThemeController.instance;
    await controller.setThemeMode(ThemeMode.dark);
    await app.launch(tester);

    await E2ePalette.run(tester, 'dark', 'querya.theme.toggle');
    await E2eAppHarness.settle(tester);
    expect(controller.themeMode, ThemeMode.light);
    expect(E2ePalette.field, findsNothing, reason: 'palette closes after run');

    await E2ePalette.run(tester, 'dark', 'querya.theme.toggle');
    await E2eAppHarness.settle(tester);
    expect(controller.themeMode, ThemeMode.dark);
    await app.close(tester);
  });

  testWidgets('unknown query shows no commands and Esc closes the palette',
      (tester) async {
    await app.launch(tester);
    await E2ePalette.open(tester);
    await E2ePalette.search(tester, 'zzzz-no-such-command');
    expect(find.byKey(const ValueKey('querya.theme.toggle')), findsNothing);
    await closeDialog(tester);
    expect(E2ePalette.field, findsNothing);
    await app.close(tester);
  });

  testWidgets('Ctrl+K opens the Quick Switcher', (tester) async {
    await app.launch(tester);
    await E2eGrid.shortcut(tester, LogicalKeyboardKey.keyK, ctrl: true);
    await E2eAppHarness.settle(tester);
    expect(find.text('Go to table, view, collection…'), findsOneWidget);
    await closeDialog(tester);
    expect(find.text('Go to table, view, collection…'), findsNothing);
    await app.close(tester);
  });
}
