import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_text_field.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('showNewConnectionUrlDialog', () {
    testWidgets('dialog shows title and form controls', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showNewConnectionUrlDialog(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('New connection from URL'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog and returns null', (tester) async {
      ConnectionRow? result;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showNewConnectionUrlDialog(context);
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('empty URL shows validation error', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showNewConnectionUrlDialog(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('URL/URI is required.'), findsOneWidget);
    });

    testWidgets('valid URL returns parsed ConnectionRow', (tester) async {
      ConnectionRow? result;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showNewConnectionUrlDialog(context);
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(QueryaTextField),
        'postgresql://user:pass@localhost:5432/mydb',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.type, 'postgresql');
      expect(result!.databaseName, 'mydb');
      expect(result!.username, 'user');
      expect(result!.password, 'pass');
    });

    group('with a save gate (#1758)', () {
      Future<void> open(
        WidgetTester tester,
        Future<String?> Function(ConnectionRow row) gate,
        void Function(ConnectionRow?) onResult,
      ) async {
        await tester.pumpWidget(
          queryaThemeTestShell(
            child: material.Builder(
              builder: (context) => material.ElevatedButton(
                onPressed: () async {
                  onResult(
                    await showNewConnectionUrlDialog(context, onSave: gate),
                  );
                },
                child: const material.Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(QueryaTextField),
          'postgresql://user:pass@localhost:5432/mydb',
        );
      }

      testWidgets('a refused save keeps the dialog and the typed URL',
          (tester) async {
        ConnectionRow? result;
        var closed = false;
        var calls = 0;
        await open(tester, (row) async {
          calls++;
          return calls == 1 ? 'The connection was not saved: keychain refused' : null;
        }, (r) {
          closed = true;
          result = r;
        });

        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(closed, isFalse);
        expect(find.text('New connection from URL'), findsOneWidget);
        expect(find.textContaining('keychain refused'), findsOneWidget);
        expect(find.text('postgresql://user:pass@localhost:5432/mydb'),
            findsOneWidget);

        // The user presses Create again; this time it is stored.
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(closed, isTrue);
        expect(result!.databaseName, 'mydb');
      });

      testWidgets('an accepted save closes the dialog with the row',
          (tester) async {
        ConnectionRow? stored;
        ConnectionRow? result;
        await open(tester, (row) async {
          stored = row;
          return null;
        }, (r) => result = r);

        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        expect(stored, isNotNull);
        expect(result, same(stored));
        expect(find.text('New connection from URL'), findsNothing);
      });
    });
  });
}
