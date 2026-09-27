import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/save_error_description.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('describeSaveError', () {
    test('SQLite read-only database', () {
      final d = describeSaveError(Exception(
        'SqfliteFfiException(sqlite_error: 8, , SqliteException(8): while executing, '
        'attempt to write a readonly database, attempt to write a readonly database (code 8)',
      ));
      expect(d.title, 'The database is read-only');
      expect(d.hint, contains('Read only'));
      expect(d.details, contains('readonly database'));
    });

    test('busy / locked database', () {
      expect(
        describeSaveError(StateError('SQLite is busy (another connection is writing). Retry in a moment.'))
            .title,
        'The database is busy',
      );
      expect(describeSaveError(Exception('database is locked')).title,
          'The database is busy');
      expect(describeSaveError(Exception('Lock wait timeout exceeded')).title,
          'The database is busy');
    });

    test('unique violations name the column or constraint', () {
      expect(
        describeSaveError(Exception('SqliteException(2067): while executing, UNIQUE constraint failed: users.email, constraint failed'))
            .message,
        contains('"email"'),
      );
      expect(
        describeSaveError(Exception('duplicate key value violates unique constraint "users_email_key"'))
            .message,
        contains('"users_email_key"'),
      );
      expect(
        describeSaveError(Exception("Duplicate entry 'a@b.c' for key 'users.email'")).title,
        'Duplicate value',
      );
    });

    test('not-null violations name the column', () {
      expect(
        describeSaveError(Exception('SqliteException(1299): while executing, NOT NULL constraint failed: users.full_name, x'))
            .message,
        '"full_name" cannot be empty.',
      );
      expect(
        describeSaveError(Exception('null value in column "name" of relation "t" violates not-null constraint'))
            .message,
        '"name" cannot be empty.',
      );
      expect(
        describeSaveError(Exception("Column 'name' cannot be null")).message,
        '"name" cannot be empty.',
      );
    });

    test('foreign key, check and type errors', () {
      expect(describeSaveError(Exception('FOREIGN KEY constraint failed')).title,
          'Related row problem');
      expect(describeSaveError(Exception('CHECK constraint failed: price')).title,
          'Value not allowed');
      expect(
        describeSaveError(Exception('invalid input syntax for type integer: "abc"')).title,
        'Wrong value type',
      );
    });

    test('stale row and duplicate-row matches', () {
      expect(
        describeSaveError(StateError('Save failed: a statement matched 0 rows. The row may have been changed or deleted.'))
            .title,
        'The row changed',
      );
      expect(
        describeSaveError(StateError('Save failed: a statement matched 2 rows instead of 1.')).title,
        'Row is not unique',
      );
    });

    test('lost connection', () {
      expect(describeSaveError(StateError('Not connected to SQLite')).title,
          'Connection lost');
    });

    test('unknown errors keep a readable first line and the full details', () {
      final d = describeSaveError(StateError('something odd\nstack line'));
      expect(d.title, 'Changes were not saved');
      expect(d.message, 'something odd');
      expect(d.details, contains('stack line'));
    });
  });

  testWidgets('save-failed dialog explains the error and reveals details',
      (tester) async {
    late material.BuildContext ctx;
    await tester.pumpWidget(queryaThemeTestShell(
      child: material.Scaffold(
        body: material.Builder(builder: (c) {
          ctx = c;
          return const material.SizedBox.shrink();
        }),
      ),
    ));

    showTableViewSaveFailedDialog(
      context: ctx,
      error: Exception('NOT NULL constraint failed: users.full_name'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Missing required value'), findsOneWidget);
    expect(find.text('"full_name" cannot be empty.'), findsOneWidget);
    expect(find.textContaining('No changes were applied'), findsOneWidget);
    expect(find.byType(material.SelectableText), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(material.SelectableText), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Missing required value'), findsNothing);
  });

  test('saved toast uses singular and plural', () {
    expect(tableViewSavedMessage(1), '1 change saved');
    expect(tableViewSavedMessage(3), '3 changes saved');
  });
}
