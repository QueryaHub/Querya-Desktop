import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_hover_surface.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show Text, TextField;

import '../helpers/e2e_app_harness.dart';
import '../helpers/e2e_connection_helper.dart';

/// #1050: connections created through the New connection dialog and the form
/// of each database type, the way a user does it.
void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_forms_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  const uriPlaceholder = {
    'postgresql': 'postgresql://user:pass@host:5432/dbname?sslmode=require',
    'mysql': 'mysql://user:pass@host:3306/dbname?ssl-mode=disable',
    'redis': 'rediss://user:pass@host:6379',
    'mongodb': 'mongodb://username:password@host:port/database',
  };

  Finder byPlaceholder(String text) => find.byWidgetPredicate((w) =>
      w is TextField &&
      w.placeholder is Text &&
      (w.placeholder as Text).data == text);

  Finder inSidebar(String text) => find.descendant(
        of: find.byType(ConnectionsPanel),
        matching: find.text(text),
      );

  Future<void> step(WidgetTester t) => t.pump(const Duration(milliseconds: 300));

  /// Waits for the form's save to reach the database (real I/O).
  Future<ConnectionRow?> savedConnection(WidgetTester t, String type) async {
    for (var i = 0; i < 60; i++) {
      final rows = await t.runAsync(() => LocalDb.instance.getConnections());
      for (final r in rows ?? const <ConnectionRow>[]) {
        if (r.type == type) {
          await step(t);
          return r;
        }
      }
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump(const Duration(milliseconds: 100));
    }
    return null;
  }

  /// Pumps with real time in between until [finder] shows: dialogs read the
  /// extension registry and secrets from disk before they open.
  Future<void> waitFor(WidgetTester t, Finder finder, String what) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets, reason: '$what did not show');
  }

  /// Picks [label] in the database type dialog and goes on to its form.
  Future<void> pickType(WidgetTester t, String label) async {
    await waitFor(t, find.text('Select your database'), 'the type dialog');
    // The type card, not the "Database type" dropdown: an open dropdown menu
    // consumes taps outside it, and in the element tree its items come before
    // the cards, so a tap on the last visible label lands on a card and only
    // closes the menu. The grid is shorter than a card here and the footer
    // covers the label, so tap the card itself (its centre is visible).
    final grid = find.byType(material.GridView);
    final text = find.descendant(of: grid, matching: find.text(label));
    // Cards past the first row are not built until the grid scrolls.
    await t.scrollUntilVisible(
      text,
      60,
      scrollable: find
          .descendant(of: grid, matching: find.byType(material.Scrollable))
          .first,
    );
    final card =
        find.ancestor(of: text, matching: find.byType(QueryaHoverSurface)).first;
    await t.ensureVisible(card);
    await step(t);
    await t.tap(card);
    await step(t);
    await t.tap(find.text('Next').hitTestable());
    await step(t);
    await step(t);
    expect(find.text('Select your database'), findsNothing,
        reason: 'Next did not leave the type dialog: $label was not selected');
  }

  Future<void> openNewConnection(WidgetTester t) async {
    await t.tap(find.byKey(const material.Key('empty_new_connection')));
    // The handler waits for the menu overlay to close before the dialog.
    await t.pump(const Duration(milliseconds: 150));
    await step(t);
  }

  // Only the URI is typed; the secure store must keep the address it names.
  final cases = <(String, String, String, String)>[
    (
      'PostgreSQL',
      'postgresql',
      'postgresql://u:p@pg.example.com:5433/app',
      'pg.example.com',
    ),
    (
      'MySQL',
      'mysql',
      'mysql://u:p@my.example.com:3307/app',
      'my.example.com',
    ),
    (
      'Redis',
      'redis',
      'redis://:p@cache.example.com:6380',
      'cache.example.com',
    ),
    (
      'MongoDB',
      'mongodb',
      'mongodb://u:p@mongo.example.com:27018/app',
      'mongo.example.com',
    ),
  ];

  for (final (label, type, uri, host) in cases) {
    testWidgets('a $label connection is created from its URI',
        (tester) async {
      await app.launch(tester);
      addTearDown(() => app.resetData(tester));
      await openNewConnection(tester);
      await pickType(tester, label);
      if (type == 'mongodb') {
        // The MongoDB form shows its URI field behind a checkbox.
        await waitFor(tester, find.text('Use connection string'), 'the form');
        await tester.tap(find.descendant(
          of: find.ancestor(
            of: find.text('Use connection string'),
            matching: find.byType(material.Row),
          ).first,
          matching: find.byType(material.Checkbox),
        ));
        await step(tester);
      }

      await waitFor(
          tester, byPlaceholder(uriPlaceholder[type]!), 'the $label form');
      await tester.enterText(byPlaceholder(uriPlaceholder[type]!), uri);
      await tester.pump();
      await tester.tap(find.text('Save').hitTestable());
      await step(tester);

      final row = await savedConnection(tester, type);
      expect(row, isNotNull, reason: '$label was not saved');
      // The URI is a secret: it goes to the secure store, not querya.db.
      expect(row!.connectionString, anyOf(isNull, isEmpty));
      final secrets = await tester
          .runAsync(() => ConnectionSecretsStore.readForConnection(row.id!));
      expect(secrets!.connectionString, contains(host));
      // The name comes from the URI's host, not the form's default one (#1257).
      expect(row.name, contains(host));
      // The sidebar reloads from the database after the save.
      await waitFor(tester, inSidebar(row.name), 'the new connection');
      await app.close(tester);
    });
  }

  testWidgets('a SQLite connection is created through its form',
      (tester) async {
    await app.launch(tester);
    addTearDown(() => app.resetData(tester));
    await openNewConnection(tester);
    await pickType(tester, 'SQLite');

    final path = '${app.dataDir.path}/e2e_form.db';
    await waitFor(
        tester, byPlaceholder('e.g. Local Cache'), 'the SQLite form');
    await tester.enterText(byPlaceholder('e.g. Local Cache'), 'E2E Form SQLite');
    await tester.pump();
    await tester.enterText(byPlaceholder('/path/to/database.db'), path);
    await tester.pump();
    await tester.tap(find.text('Save'));
    // Saving creates the database file: real I/O.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    final row = await savedConnection(tester, 'sqlite');
    expect(row, isNotNull);
    expect(row!.name, 'E2E Form SQLite');
    expect(row.host, path);
    expect(inSidebar('E2E Form SQLite'), findsOneWidget);
    await app.close(tester);
  });

  testWidgets('New connection on a folder saves the connection into it',
      (tester) async {
    await app.launch(tester);
    addTearDown(() => app.resetData(tester));
    await tester.runAsync(() => FoldersStorage.instance.add('Team Forms'));
    addTearDown(() =>
        tester.runAsync(() => FoldersStorage.instance.remove('Team Forms')));
    // An existing connection keeps the sidebar out of its empty state.
    await E2eConnections.add(tester, E2eConnections.redis('E2E Anchor'));
    await tester.runAsync(FoldersStorage.instance.reload);
    await E2eConnections.reloadSidebar(tester);
    await waitFor(tester, inSidebar('Team Forms'), 'the folder');
    final folderId = await tester
        .runAsync(() => LocalDb.instance.getFolderIdByName('Team Forms'));
    expect(folderId, isNotNull);

    await tester.tap(inSidebar('Team Forms'), buttons: kSecondaryButton);
    await step(tester);
    await tester.tap(find.text('New connection').last);
    // The handler reads the folder id from disk before the dialog.
    await tester.pump(const Duration(milliseconds: 150));
    await step(tester);
    await pickType(tester, 'PostgreSQL');

    final uriField = byPlaceholder(uriPlaceholder['postgresql']!);
    await waitFor(tester, uriField, 'the PostgreSQL form');
    await tester.enterText(uriField, 'postgresql://u:p@folder.example.com:5432/app');
    await tester.pump();
    await tester.enterText(byPlaceholder('My PostgreSQL Server'), 'E2E Foldered');
    await tester.pump();
    await tester.tap(find.text('Save').hitTestable());
    await step(tester);

    final row = await savedConnection(tester, 'postgresql');
    expect(row, isNotNull, reason: 'the connection was not saved');
    expect(row!.name, 'E2E Foldered');
    expect(row.folderId, folderId);
    await app.close(tester);
  });
}
