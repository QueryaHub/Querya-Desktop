import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:querya_desktop/features/mongodb/mongo_document_tree_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_json_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_table_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_view.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

final _docs = <Map<String, dynamic>>[
  {
    '_id': ObjectId.fromHexString('507f1f77bcf86cd799439011'),
    'name': 'Querya',
    'address': {
      'city': 'Berlin',
      'geo': [
        {'lat': 52.5},
      ],
    },
  },
  {
    '_id': ObjectId.fromHexString('507f1f77bcf86cd799439012'),
    'name': 'MongoDB',
  },
];

/// Switches between the same document set in the Table / Tree / JSON viewers,
/// the way [MongoDocumentsView] does after a view-mode change.
class _Viewer extends material.StatefulWidget {
  const _Viewer({this.onDocumentTap});

  final void Function(Map<String, dynamic>)? onDocumentTap;

  @override
  material.State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends material.State<_Viewer> {
  MongoDocumentsViewMode _mode = MongoDocumentsViewMode.table;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      body: material.Column(
        children: [
          material.Row(
            children: [
              for (final mode in const [
                MongoDocumentsViewMode.table,
                MongoDocumentsViewMode.tree,
                MongoDocumentsViewMode.json,
              ])
                material.TextButton(
                  onPressed: () => setState(() => _mode = mode),
                  child: material.Text('mode:${mode.id}'),
                ),
            ],
          ),
          material.Expanded(
            child: switch (_mode) {
              MongoDocumentsViewMode.tree => MongoDocumentTreeView(
                  documents: _docs,
                  onDocumentTap: widget.onDocumentTap,
                ),
              MongoDocumentsViewMode.json =>
                MongoDocumentsJsonView(documents: _docs),
              _ => MongoDocumentsTableView(
                  documents: _docs,
                  onDocumentTap: widget.onDocumentTap,
                ),
            },
          ),
        ],
      ),
    );
  }
}

void main() {
  Future<void> open(WidgetTester tester,
      {void Function(Map<String, dynamic>)? onDocumentTap}) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(child: _Viewer(onDocumentTap: onDocumentTap)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('table → tree → JSON keep showing the same documents',
      timeout: _timeout, (tester) async {
    await open(tester);

    expect(find.byType(MongoDocumentsTableView), findsOneWidget);
    expect(
      find.text(
          '2 rows · Click a row to select · Click column header to sort'),
      findsOneWidget,
    );

    await tester.tap(find.text('mode:tree'));
    await tester.pumpAndSettle();
    expect(find.byType(MongoDocumentTreeView), findsOneWidget);
    expect(find.text('"Querya"'), findsOneWidget);
    expect(find.text('"MongoDB"'), findsOneWidget);

    await tester.tap(find.text('mode:json'));
    await tester.pumpAndSettle();
    expect(find.byType(MongoDocumentsJsonView), findsOneWidget);

    await tester.tap(find.text('mode:table'));
    await tester.pumpAndSettle();
    expect(find.byType(MongoDocumentsTableView), findsOneWidget);
  });

  testWidgets('tree view folds nested fields with Collapse All / Expand All',
      timeout: _timeout, (tester) async {
    await open(tester);
    await tester.tap(find.text('mode:tree'));
    await tester.pumpAndSettle();

    expect(find.text('address'), findsOneWidget);
    expect(find.text('"Berlin"'), findsOneWidget);

    await tester.tap(find.text('Collapse All'));
    await tester.pumpAndSettle();
    expect(find.text('"Querya"'), findsNothing);
    expect(find.text('"Berlin"'), findsNothing);

    await tester.tap(find.text('Expand All'));
    await tester.pumpAndSettle();
    expect(find.text('"Querya"'), findsOneWidget);
    expect(find.text('"Berlin"'), findsOneWidget);
  });
}
