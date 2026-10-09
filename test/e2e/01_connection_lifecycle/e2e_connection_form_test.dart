import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show Text, TextField;

import '../helpers/e2e_app_harness.dart';

/// #1050: connections created through the New connection dialog and the form
/// of each database type, the way a user does it.
void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_forms_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  const _uriPlaceholder = {
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
  Future<void> waitFor(WidgetTester t, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Picks [label] in the database type dialog and goes on to its form.
  Future<void> pickType(WidgetTester t, String label) async {
    await waitFor(t, find.text('Select your database'));
    expect(find.text('Select your database'), findsOneWidget);
    await t.tap(find.text('Select database…'));
    await step(t);
    // Only the visible item: the picker's own label is in the tree too.
    await t.tap(find.text(label).hitTestable().last);
    await step(t);
    await t.tap(find.text('Next').hitTestable());
    await step(t);
    await step(t);
  }

  Future<void> openNewConnection(WidgetTester t) async {
    await t.tap(find.byKey(const material.Key('empty_new_connection')));
    // The handler waits for the menu overlay to close before the dialog.
    await t.pump(const Duration(milliseconds: 150));
    await step(t);
  }

  // The name of a URI connection comes from its address, so only the URI is
  // typed; the saved row must carry the host it names.
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

      await waitFor(tester, byPlaceholder(_uriPlaceholder[type]!));
      await tester.enterText(byPlaceholder(_uriPlaceholder[type]!), uri);
      await tester.pump();
      await tester.tap(find.text('Save').hitTestable());
      await step(tester);

      final row = await savedConnection(tester, type);
      expect(row, isNotNull, reason: '$label was not saved');
      expect('${row!.host} ${row.connectionString}', contains(host));
      expect(row.name, contains(host));
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
    await waitFor(tester, byPlaceholder('e.g. Local Cache'));
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
}
