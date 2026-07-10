import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
        find.byType(TextField),
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
  });
}
