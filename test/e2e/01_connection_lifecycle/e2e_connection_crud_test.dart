import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_connection_helper.dart';

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_crud_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  Finder inSidebar(String text) => find.descendant(
        of: find.byType(ConnectionsPanel),
        matching: find.text(text),
      );

  testWidgets('every supported type is created, edited and removed',
      (tester) async {
    await app.launch(tester);
    final rows = {
      'E2E PG': E2eConnections.postgres('E2E PG'),
      'E2E MySQL': E2eConnections.mysql('E2E MySQL'),
      'E2E Mongo': E2eConnections.mongo('E2E Mongo'),
      'E2E Redis': E2eConnections.redis('E2E Redis'),
      'E2E SQLite': E2eConnections.sqlite('E2E SQLite', '/tmp/e2e.db'),
    };
    final ids = <String, int>{};
    for (final e in rows.entries) {
      ids[e.key] = await E2eConnections.add(tester, e.value);
    }
    for (final name in rows.keys) {
      expect(inSidebar(name), findsOneWidget, reason: name);
    }

    // Edit: rename one connection and change its port.
    final stored = await tester.runAsync(
        () => LocalDb.instance.getConnectionById(ids['E2E PG']!));
    await tester.runAsync(() => LocalDb.instance
        .updateConnection(stored!.copyWith(name: 'E2E PG renamed', port: 5433)));
    await E2eConnections.reloadSidebar(tester);
    expect(inSidebar('E2E PG renamed'), findsOneWidget);
    expect(inSidebar('E2E PG'), findsNothing);
    final edited = await tester.runAsync(
        () => LocalDb.instance.getConnectionById(ids['E2E PG']!));
    expect(edited!.port, 5433);

    for (final id in ids.values) {
      await E2eConnections.remove(tester, id);
    }
    expect(inSidebar('E2E Redis'), findsNothing);
    final left = await tester.runAsync(() => LocalDb.instance.getConnections());
    expect(left, isEmpty);
    await app.close(tester);
  });

  testWidgets('folders can be created and removed', (tester) async {
    await app.launch(tester);
    await tester.runAsync(() => FoldersStorage.instance.add('Team A'));
    expect(FoldersStorage.instance.folders, contains('Team A'));
    await tester.runAsync(() => FoldersStorage.instance.remove('Team A'));
    expect(FoldersStorage.instance.folders, isNot(contains('Team A')));
    await app.close(tester);
  });
}
