import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/main_screen/main_screen.dart';

import '../../support/querya_theme_test_shell.dart';
import '../helpers/e2e_app_harness.dart';

/// A VS Code theme as users paste it: comments and trailing commas (JSONC).
const _jsonc = '''
{
  // Exported from VS Code.
  "name": "E2E Night",
  "type": "dark",
  "colors": {
    "editor.background": "#101820",
    "sideBar.background": "#0b1016", // the sidebar
    "foreground": "#e6e6e6",
  },
}
''';

/// #1053: a theme imported from VS Code recolours the running app, and the
/// switch never passes through a light frame.
void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_theme_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  QueryaTheme themeIn(WidgetTester t) =>
      QueryaThemeScope.of(t.element(find.byType(ConnectionsPanel)));

  testWidgets('an imported JSONC theme recolours the running app',
      (tester) async {
    final imported =
        buildQueryaThemeFromVsCodeManifest(VsCodeThemeManifest.fromJsonString(_jsonc));
    expect(imported.workbench.editorBackground, const material.Color(0xFF101820));
    expect(imported.workbench.sidebarBackground, const material.Color(0xFF0B1016));

    final active = material.ValueNotifier<QueryaTheme>(QueryaTheme.darkDefault);
    addTearDown(active.dispose);
    await tester.binding.setSurfaceSize(const material.Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(material.ValueListenableBuilder<QueryaTheme>(
      valueListenable: active,
      builder: (context, theme, _) => queryaThemeTestShell(
        data: theme,
        child: const material.SizedBox(
            width: 1400, height: 900, child: MainScreen()),
      ),
    ));
    await E2eAppHarness.settle(tester);
    expect(themeIn(tester).workbench.sidebarBackground,
        QueryaTheme.darkDefault.workbench.sidebarBackground);
    final panel = tester.state(find.byType(ConnectionsPanel));

    active.value = imported;
    // Every frame of the switch stays dark: no white flash.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final w = themeIn(tester).workbench;
      expect(w.sidebarBackground.computeLuminance(), lessThan(0.2),
          reason: 'frame $i');
      expect(w.editorBackground.computeLuminance(), lessThan(0.2),
          reason: 'frame $i');
    }
    expect(themeIn(tester).workbench.sidebarBackground,
        const material.Color(0xFF0B1016));
    expect(themeIn(tester).workbench.editorBackground,
        const material.Color(0xFF101820));
    // The app was recoloured in place, not rebuilt from scratch.
    expect(identical(tester.state(find.byType(ConnectionsPanel)), panel), isTrue);
    expect(tester.takeException(), isNull);

    // And back to the built-in theme.
    active.value = QueryaTheme.darkDefault;
    await tester.pump();
    expect(themeIn(tester).workbench.sidebarBackground,
        QueryaTheme.darkDefault.workbench.sidebarBackground);
    await app.close(tester);
  });

  test('a theme that is not JSON is refused with a clear error', () {
    expect(
      () => VsCodeThemeManifest.fromJsonString('{ "colors": '),
      throwsA(isA<VsCodeThemeParseException>()),
    );
  });
}
