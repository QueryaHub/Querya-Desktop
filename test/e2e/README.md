# End-to-end tests

Scenario tests that drive the real `MainScreen` through user actions (sidebar,
Command Palette, grid keyboard shortcuts). They run with plain `flutter test`
— no device, no database server: the app starts on an isolated data directory,
an empty `LocalDb` and in-memory secrets.

```bash
flutter test test/e2e
```

## Layout

| Path | Purpose |
| --- | --- |
| `helpers/e2e_app_harness.dart` | `E2eAppHarness`: isolated data dir, virtual screen, `launch()` |
| `helpers/e2e_connection_helper.dart` | `E2eConnections`: create / list / open / remove connections (Postgres, MySQL, Mongo, Redis, SQLite, extension) |
| `helpers/e2e_grid_interactions.dart` | `E2eGrid`: shortcuts (`Ctrl+F`, `Ctrl+G`, `Enter`, `Esc`), cell tap / edit, staging-buffer assertions |
| `helpers/e2e_command_palette_helper.dart` | `E2ePalette`: `Ctrl+P`, search, select / run a command |
| `e2e_smoke_test.dart` | app start, palette, sidebar |

New scenarios go into `test/e2e/<section>_test.dart` (one file per product area).

## Writing a scenario

```dart
void main() {
  final app = E2eAppHarness();
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  testWidgets('create and remove a connection', (tester) async {
    await app.launch(tester);
    final id = await E2eConnections.add(tester, E2eConnections.redis('cache'));
    expect(find.text('cache'), findsOneWidget);
    await E2eConnections.remove(tester, id);
  });
}
```

## Rules

- Keep a scenario under ~30 lines; put repeated steps into a helper.
- Real database servers are out of scope here — use the fakes in `test/support/`
  (`FakeSqlExecutionDelegate`, `FakeTableDataDelegate`, `fake_ssh.dart`).
- Data from the database goes through `runAsync`; after UI actions `pump` with a
  duration instead of `pumpAndSettle` (spinners never settle).
- Call `app.resetData(tester)` in `tearDown` when a test leaves connections behind.
