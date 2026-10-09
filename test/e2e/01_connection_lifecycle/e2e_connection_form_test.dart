import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
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

  /// Picks [label] in the database type dialog and goes on to its form.
  Future<void> pickType(WidgetTester t, String label) async {
    expect(find.text('Select your database'), findsOneWidget);
    await t.tap(find.text('Select database…'));
    await step(t);
    await t.tap(find.text(label).last);
    await step(t);
    await t.tap(find.text('Next'));
    await step(t);
    await step(t);
  }

  Future<void> openNewConnection(WidgetTester t) async {
    await t.tap(find.byKey(const material.Key('empty_new_connection')));
    // The handler waits for the menu overlay to close before the dialog.
    await t.pump(const Duration(milliseconds: 150));
    await step(t);
  }

  final cases = <(String, String, String, Map<String, String>, String)>[
    (
      'PostgreSQL',
      'postgresql',
      'E2E Form PG',
      {
        'postgresql://user:pass@host:5432/dbname?sslmode=require':
            'postgresql://u:p@pg.example.com:5433/app',
        'My PostgreSQL Server': 'E2E Form PG',
      },
      'pg.example.com',
    ),
    (
      'MySQL',
      'mysql',
      'E2E Form MySQL',
      {
        'mysql://user:pass@host:3306/dbname?ssl-mode=disable':
            'mysql://u:p@my.example.com:3307/app',
        'My MySQL Server': 'E2E Form MySQL',
      },
      'my.example.com',
    ),
    (
      'Redis',
      'redis',
      'E2E Form Redis',
      {
        'rediss://user:pass@host:6379': 'redis://:p@cache.example.com:6380',
        'My Redis Server': 'E2E Form Redis',
      },
      'cache.example.com',
    ),
    (
      'MongoDB',
      'mongodb',
      'E2E Form Mongo',
      {
        'mongodb://username:password@host:port/database':
            'mongodb://u:p@mongo.example.com:27018/app',
        'My MongoDB Server': 'E2E Form Mongo',
      },
      'mongo.example.com',
    ),
  ];

  for (final (label, type, name, fields, host) in cases) {
    testWidgets('a $label connection is created through its form',
        (tester) async {
      await app.launch(tester);
      addTearDown(() => app.resetData(tester));
      await openNewConnection(tester);
      await pickType(tester, label);

      for (final e in fields.entries) {
        await tester.enterText(byPlaceholder(e.key), e.value);
        await tester.pump();
      }
      await tester.tap(find.text('Save'));
      await step(tester);

      final row = await savedConnection(tester, type);
      expect(row, isNotNull, reason: '$label was not saved');
      expect(row!.name, name);
      // The URI fills the host, or is kept as the connection string.
      expect('${row.host} ${row.connectionString}', contains(host));
      expect(inSidebar(name), findsOneWidget);
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
      variant: TargetPlatformVariant.only(material.TargetPlatform.linux),
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
    final folderId = await tester
        .runAsync(() => LocalDb.instance.getFolderIdByName('Team Forms'));

    await tester.tap(inSidebar('Team Forms'), buttons: kSecondaryButton);
    await step(tester);
    await tester.tap(find.text('New connection').last);
    await tester.pump(const Duration(milliseconds: 150));
    await step(tester);
    await pickType(tester, 'PostgreSQL');
    await tester.enterText(
        byPlaceholder('postgresql://user:pass@host:5432/dbname?sslmode=require'),
        'postgresql://u:p@folder.example.com:5432/app');
    await tester.pump();
    await tester.enterText(
        byPlaceholder('My PostgreSQL Server'), 'E2E Foldered');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await step(tester);

    final row = await savedConnection(tester, 'postgresql');
    expect(row, isNotNull);
    expect(row!.name, 'E2E Foldered');
    expect(row.folderId, folderId);
    await app.close(tester);
  });
}
