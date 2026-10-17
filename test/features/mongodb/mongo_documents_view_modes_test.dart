import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_highlight_controller.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_semantic_palette.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/mongodb/mongo_document_tree_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_json_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_table_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('MongoDocumentsViewMode', () {
    test('fromString parses correctly and defaults to table', () {
      expect(MongoDocumentsViewMode.fromString('table'), MongoDocumentsViewMode.table);
      expect(MongoDocumentsViewMode.fromString('tree'), MongoDocumentsViewMode.tree);
      expect(MongoDocumentsViewMode.fromString('json'), MongoDocumentsViewMode.json);
      expect(MongoDocumentsViewMode.fromString('cards'), MongoDocumentsViewMode.cards);
      expect(MongoDocumentsViewMode.fromString('unknown'), MongoDocumentsViewMode.table);
      expect(MongoDocumentsViewMode.fromString(null), MongoDocumentsViewMode.table);
    });
  });

  group('appendJsonPath', () {
    test('constructs JSON paths according to specification', () {
      expect(appendJsonPath('', 'address'), 'address');
      expect(appendJsonPath('address', 'geo'), 'address.geo');
      expect(appendJsonPath('address.geo', 0), 'address.geo[0]');
      expect(appendJsonPath('address.geo[0]', 'lat'), 'address.geo[0].lat');
      expect(appendJsonPath('user', 'first-name'), 'user["first-name"]');
      // Identifier characters (#1525): `_`, `$`, digits after the first.
      expect(appendJsonPath('doc', r'$id'), r'doc.$id');
      expect(appendJsonPath('doc', '_x9'), 'doc._x9');
      expect(appendJsonPath('doc', 'A'), 'doc.A');
      // Not identifiers: leading digit, empty, space, dot, non-ASCII, quote.
      expect(appendJsonPath('doc', '9x'), 'doc["9x"]');
      expect(appendJsonPath('doc', ''), 'doc[""]');
      expect(appendJsonPath('doc', 'a b'), 'doc["a b"]');
      expect(appendJsonPath('doc', 'a.b'), 'doc["a.b"]');
      expect(appendJsonPath('doc', 'caf\u00e9'), 'doc["caf\u00e9"]');
      expect(appendJsonPath('doc', 'say"hi'), r'doc["say\"hi"]');
      expect(appendJsonPath('data', 'space key'), 'data["space key"]');
    });
  });

  group('mongoDocumentsToEjson', () {
    test('formats empty list as empty JSON array', () {
      expect(mongoDocumentsToEjson([]), '[]');
    });

    test('formats list of documents into relaxed EJSON array', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final docs = [
        {
          '_id': id,
          'name': 'Test',
          'nested': {'k': 'v'},
          'items': [1, 2],
        }
      ];
      final json = mongoDocumentsToEjson(docs);
      expect(json, contains(r'$oid'));
      expect(json, contains('507f1f77bcf86cd799439011'));
      expect(json, contains('"name": "Test"'));
      expect(json, contains('"items": ['));
    });
  });

  group('MongoTableGridData', () {
    test('extracts columns with _id first and formats nested badges', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final docs = [
        {
          'title': 'Hello',
          '_id': id,
          'author': {
            'first': 'Jane',
            'last': 'Doe',
          },
          'tags': ['a', 'b', 'c'],
          'views': 42,
          'active': true,
          'notes': null,
        },
        {
          '_id': ObjectId.fromHexString('507f1f77bcf86cd799439012'),
          'title': 'World',
          'extra': 'value',
        }
      ];

      final grid = MongoTableGridData.fromDocuments(docs);

      // _id must be first
      expect(grid.columns.first, '_id');
      expect(grid.columns, containsAll(['_id', 'author', 'tags', 'title', 'views', 'active', 'notes', 'extra']));

      // Inferred types
      expect(grid.columnDataTypes['_id'], 'ObjectId');
      expect(grid.columnDataTypes['author'], 'Object');
      expect(grid.columnDataTypes['tags'], 'Array');
      expect(grid.columnDataTypes['views'], 'Int32');
      expect(grid.columnDataTypes['active'], 'Boolean');
      expect(grid.columnDataTypes['title'], 'String');

      // Formatted cells for first doc
      final row0 = grid.rows[0];
      final idIndex = grid.columns.indexOf('_id');
      final authorIndex = grid.columns.indexOf('author');
      final tagsIndex = grid.columns.indexOf('tags');
      final notesIndex = grid.columns.indexOf('notes');

      expect(row0[idIndex], '507f1f77bcf86cd799439011');
      expect(row0[authorIndex], '{ 2 fields }');
      expect(row0[tagsIndex], '[ 3 items ]');
      expect(row0[notesIndex], 'NULL');

      // Formatted cells for second doc (missing fields are empty string)
      final row1 = grid.rows[1];
      expect(row1[authorIndex], '');
    });
  });

  group('MongoDocumentsTableView widget', () {
    testWidgets('renders table grid view and status bar', (tester) async {
      final docs = [
        {
          '_id': ObjectId.fromHexString('507f1f77bcf86cd799439011'),
          'name': 'Querya',
        },
        {
          '_id': ObjectId.fromHexString('507f1f77bcf86cd799439012'),
          'name': 'MongoDB',
        },
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoDocumentsTableView(
            documents: docs,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MongoDocumentsTableView), findsOneWidget);
      expect(find.text('2 rows · Click a row to select · Click column header to sort'), findsOneWidget);
    });
  });

  group('MongoDocumentTreeView widget', () {
    testWidgets('renders document tree with folding and search', (tester) async {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final docs = [
        {
          '_id': id,
          'name': 'Doc1',
          'address': {
            'geo': [
              {'lat': 10.0}
            ]
          }
        },
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoDocumentTreeView(
            documents: docs,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MongoDocumentTreeView), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('"Doc1"'), findsOneWidget);
      expect(find.text('address'), findsOneWidget);
      expect(find.text('Expand All'), findsOneWidget);
      expect(find.text('Collapse All'), findsOneWidget);

      // Tap Collapse All
      await tester.tap(find.text('Collapse All'));
      await tester.pumpAndSettle();

      // Tap Expand All
      await tester.tap(find.text('Expand All'));
      await tester.pumpAndSettle();
      expect(find.text('address'), findsOneWidget);
    });

    testWidgets('colors leaf values using semantic palette tokens (#1644)',
        (tester) async {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final date = DateTime.utc(2026, 1, 1);
      final docs = [
        {
          '_id': id,
          'strField': 'hello',
          'numField': 42,
          'boolField': true,
          'dateField': date,
          'nullField': null,
        },
      ];

      const theme = QueryaTheme.darkDefault;
      final palette = QueryaSemanticPalette.fromTheme(theme);

      await tester.pumpWidget(
        queryaThemeTestShell(
          data: theme,
          child: MongoDocumentTreeView(
            documents: docs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final strText = tester.widget<material.Text>(find.text('"hello"'));
      expect(strText.style?.color, palette.type1);

      final numText = tester.widget<material.Text>(find.text('42'));
      expect(numText.style?.color, palette.type2);

      final boolText = tester.widget<material.Text>(find.text('true'));
      expect(boolText.style?.color, palette.type3);

      final nullText = tester.widget<material.Text>(
        find.byWidgetPredicate(
          (w) =>
              w is material.Text &&
              w.data == 'null' &&
              w.style?.fontStyle == material.FontStyle.italic,
        ),
      );
      expect(nullText.style?.color, palette.muted);
    });
  });

  group('MongoDocumentsJsonView widget', () {
    testWidgets('renders code editor and copy button', (tester) async {
      final docs = [
        {
          'field': 'value',
        }
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoDocumentsJsonView(
            documents: docs,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MongoDocumentsJsonView), findsOneWidget);
      expect(find.text('Copy JSON'), findsOneWidget);
      expect(find.text('1 documents (Extended JSON)'), findsOneWidget);
    });

    testWidgets('uses QueryaHighlightController when syntax highlighting is initialized', (tester) async {
      await SyntaxHighlightService.ensureInitialized();
      final docs = [
        {'field': 'value'}
      ];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoDocumentsJsonView(
            documents: docs,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final editor = tester.widget<QueryaCodeEditor>(find.byType(QueryaCodeEditor));
      expect(editor.controller, isA<QueryaHighlightController>());
    });
  });
}
