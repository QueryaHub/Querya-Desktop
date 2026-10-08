import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:querya_desktop/features/main_screen/main_screen.dart';

import 'helpers/e2e_app_harness.dart';
import 'helpers/e2e_command_palette_helper.dart';
import 'helpers/e2e_connection_helper.dart';

void main() {
  final app = E2eAppHarness();
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  testWidgets('app starts and shows the main shell', (tester) async {
    await app.launch(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(ConnectionsPanel), findsOneWidget);
    expect(find.byKey(const Key('empty_new_connection')), findsOneWidget);
  });

  testWidgets('command palette opens with Ctrl+P and closes on Escape',
      (tester) async {
    await app.launch(tester);
    await E2ePalette.open(tester);
    expect(E2ePalette.field, findsOneWidget);
    await E2ePalette.search(tester, 'dark');
    expect(find.byKey(const ValueKey('querya.theme.toggle')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(E2ePalette.field, findsNothing);
  });

  testWidgets('a stored connection appears in the sidebar', (tester) async {
    await app.launch(tester);
    final id = await E2eConnections.add(
        tester, E2eConnections.postgres('E2E Postgres'));
    expect(find.text('E2E Postgres'), findsOneWidget);
    await E2eConnections.remove(tester, id);
    expect(find.text('E2E Postgres'), findsNothing);
  });
}
