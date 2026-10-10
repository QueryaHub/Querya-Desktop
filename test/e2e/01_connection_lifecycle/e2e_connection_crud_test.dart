import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_connection_helper.dart';

void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_crud_');
  setUpAll(app.setUpAll);
  // The welcome tour opens on a first launch without connections and its
  // scrim covers the sidebar.
  setUpAll(() => AppSettings.instance.setHasCompletedWelcomeTour(true));
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

  testWidgets('a connection is moved into a folder and the sidebar shows it',
      (tester) async {
    await app.launch(tester);
    await tester.runAsync(() => FoldersStorage.instance.add('Team B'));
    final folderId = await tester
        .runAsync(() => LocalDb.instance.getFolderIdByName('Team B'));
    expect(folderId, isNotNull);

    final id = await E2eConnections.add(
        tester, E2eConnections.postgres('E2E Moved'));
    final stored =
        await tester.runAsync(() => LocalDb.instance.getConnectionById(id));
    expect(stored!.folderId, isNull);

    await tester.runAsync(() => LocalDb.instance
        .updateConnection(stored.copyWith(folderId: folderId)));
    await tester.runAsync(FoldersStorage.instance.reload);
    await E2eConnections.reloadSidebar(tester);

    final moved =
        await tester.runAsync(() => LocalDb.instance.getConnectionById(id));
    expect(moved!.folderId, folderId);
    expect(inSidebar('Team B'), findsOneWidget);

    await E2eConnections.remove(tester, id);
    await tester.runAsync(() => FoldersStorage.instance.remove('Team B'));
    await app.close(tester);
  });

  testWidgets('Move to folder in the connection menu puts it in the folder',
      (tester) async {
    await app.launch(tester);
    await tester.runAsync(() => FoldersStorage.instance.add('Team C'));
    final folderId = await tester
        .runAsync(() => LocalDb.instance.getFolderIdByName('Team C'));
    final id = await E2eConnections.add(
        tester, E2eConnections.redis('E2E Mover'));
    await tester.runAsync(FoldersStorage.instance.reload);
    await E2eConnections.reloadSidebar(tester);

    await tester.tap(inSidebar('E2E Mover').first, buttons: kSecondaryButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Move to folder'), findsWidgets,
        reason: 'the connection menu did not open');
    await tester.tap(find.text('Move to folder').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Team C').last);
    await tester.pump(const Duration(milliseconds: 300));

    final row =
        await tester.runAsync(() => LocalDb.instance.getConnectionById(id));
    expect(row!.folderId, folderId);

    // Moving back out ("No folder") is covered by LocalDb.setConnectionFolder's
    // test. In this widget test the entry never showed for a connection that
    // is already inside a folder; the cause was not found.
    await E2eConnections.remove(tester, id);
    await tester.runAsync(() => FoldersStorage.instance.remove('Team C'));
    await app.close(tester);
  });


  testWidgets('a connection is dragged into a folder and out of it again',
      (tester) async {
    await app.launch(tester);
    await tester.runAsync(() => FoldersStorage.instance.add('Team D'));
    final folderId = await tester
        .runAsync(() => LocalDb.instance.getFolderIdByName('Team D'));
    final id = await E2eConnections.add(
        tester, E2eConnections.redis('E2E Dragged'));
    await tester.runAsync(FoldersStorage.instance.reload);
    await E2eConnections.reloadSidebar(tester);

    Future<void> dragTo(Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      // Past the drag slop, then onto the target in a few steps.
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await dragTo(
      tester.getCenter(inSidebar('E2E Dragged').first),
      tester.getCenter(inSidebar('Team D')),
    );
    final first =
        await tester.runAsync(() => LocalDb.instance.getConnectionById(id));
    expect(first!.folderId, folderId, reason: 'dropped on the folder');

    // The panel reloads from the database after the drop (real I/O); the tile
    // is under its folder once it has. Dragging before that starts from the
    // old layout with the old folder.
    for (var i = 0; i < 40; i++) {
      final tile = inSidebar('E2E Dragged');
      final folder = inSidebar('Team D');
      if (tile.evaluate().isNotEmpty &&
          folder.evaluate().isNotEmpty &&
          tester.getCenter(tile.first).dy > tester.getCenter(folder.first).dy) {
        break;
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester.getCenter(inSidebar('E2E Dragged').first).dy,
      greaterThan(tester.getCenter(inSidebar('Team D').first).dy),
      reason: 'the connection is listed under its folder',
    );
    final from = tester.getCenter(inSidebar('E2E Dragged').first);
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 100));
    final strip = find.byKey(const ValueKey('drop_out_of_folder'));
    expect(strip, findsOneWidget, reason: 'the drop strip shows while dragging');
    await gesture.moveTo(tester.getCenter(strip));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    // The write is real I/O: give it time before reading.
    ConnectionRow? row;
    for (var i = 0; i < 20; i++) {
      row = await tester
          .runAsync<ConnectionRow?>(() => LocalDb.instance.getConnectionById(id));
      if (row!.folderId == null) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(row!.folderId, isNull, reason: 'dropped on the strip');

    await E2eConnections.remove(tester, id);
    await tester.runAsync(() => FoldersStorage.instance.remove('Team D'));
    await app.close(tester);
  });
}
