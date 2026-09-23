import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/features/mongodb/mongo_add_document_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('showMongoAddDocumentDialog', () {
    testWidgets(
        'dialog shows Add Document title, target collection, and buttons',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showMongoAddDocumentDialog(
                context,
                database: 'analytics',
                collection: 'events',
              ),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Add Document'), findsOneWidget);
      expect(
        find.text('Insert a new document into analytics.events.'),
        findsOneWidget,
      );
      expect(find.text('Document (Extended JSON)'), findsOneWidget);
      expect(find.byType(QueryaCodeEditor), findsOneWidget);
      expect(find.text('Insert Document'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog and returns null', (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showMongoAddDocumentDialog(
                  context,
                  database: 'analytics',
                  collection: 'events',
                );
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

    testWidgets('Invalid EJSON displays error banner and does not close dialog',
        (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showMongoAddDocumentDialog(
                  context,
                  database: 'analytics',
                  collection: 'events',
                );
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter invalid JSON
      await tester.enterText(
          find.byType(material.EditableText), '{broken json:');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Insert Document'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid EJSON syntax'), findsOneWidget);
      expect(result, isNull);
      expect(find.text('Add Document'), findsOneWidget);
    });

    testWidgets('Valid EJSON closes dialog and returns parsed document',
        (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showMongoAddDocumentDialog(
                  context,
                  database: 'analytics',
                  collection: 'events',
                );
              },
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter valid EJSON
      await tester.enterText(
        find.byType(material.EditableText),
        '{"status": "active", "views": 10}',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Insert Document'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!['status'], 'active');
      expect(result!['views'], 10);
      expect(find.text('Add Document'), findsNothing);
    });
  });
}
