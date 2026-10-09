import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_add_document_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongo_collections_view.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_view.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

/// A connection that lists two collections and never opens a socket.
class _Connection extends MongoConnection {
  _Connection() : super(id: 11, name: 'shop-mongo', host: 'localhost');

  @override
  Future<List<String>> listCollections(String databaseName) async =>
      const ['orders', 'users'];
}

/// Documents in memory, with every write recorded.
class _FakeMongo extends MongoService {
  _FakeMongo() : super.forTest();

  final docs = <Map<String, dynamic>>[
    {'_id': 1, 'name': 'ann', 'city': 'Berlin'},
    {'_id': 2, 'name': 'bob', 'city': 'Paris'},
  ];
  final inserted = <Map<String, dynamic>>[];
  final updates = <(Map<String, dynamic>, Map<String, dynamic>)>[];
  final deletes = <Map<String, dynamic>>[];
  var nextId = 3;

  @override
  Future<List<Map<String, dynamic>>> find(
    MongoConnection connection,
    String database,
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? projection,
    Map<String, dynamic>? sort,
    int? limit,
    int? skip,
  }) async =>
      [for (final d in docs) Map<String, dynamic>.of(d)];

  @override
  Future<int> countDocuments(
    MongoConnection connection,
    String database,
    String collection, {
    Map<String, dynamic>? filter,
  }) async =>
      docs.length;

  @override
  Future<Map<String, dynamic>> insertDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> document,
  ) async {
    inserted.add(document);
    docs.add({'_id': nextId++, ...document});
    return document;
  }

  @override
  Future<void> updateDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    updates.add((filter, update));
    final doc = docs.firstWhere((d) => d['_id'] == filter['_id']);
    doc.addAll((update[r'$set'] as Map).cast<String, dynamic>());
  }

  @override
  Future<void> deleteDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
  ) async {
    deletes.add(filter);
    docs.removeWhere((d) => d['_id'] == filter['_id']);
  }
}

/// The sidebar's collection list, and the documents of the one picked.
class _Explorer extends material.StatefulWidget {
  const _Explorer(this.connection);

  final MongoConnection connection;

  @override
  material.State<_Explorer> createState() => _ExplorerState();
}

class _ExplorerState extends material.State<_Explorer> {
  String? _collection;

  @override
  material.Widget build(material.BuildContext context) {
    final collection = _collection;
    return material.Scaffold(
      body: collection == null
          ? MongoCollectionsView(
              connection: widget.connection,
              database: 'shop',
              onCollectionTap: (name) => setState(() => _collection = name),
            )
          : MongoDocumentsView(
              connection: widget.connection,
              database: 'shop',
              collection: collection,
              initialViewMode: MongoDocumentsViewMode.cards,
            ),
    );
  }
}

void main() {
  late _FakeMongo mongo;

  setUp(() {
    mongo = _FakeMongo();
    MongoService.instanceForTest = mongo;
  });
  tearDown(() => MongoService.instanceForTest = null);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'collections open into documents; add, edit and delete a document (#1052)',
      timeout: _timeout, (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(queryaThemeTestShell(child: _Explorer(_Connection())));
    await settle(tester);

    // The collections of the database, and a tap opens one.
    expect(find.text('orders'), findsOneWidget);
    expect(find.text('users'), findsOneWidget);
    await tester.tap(find.text('orders'));
    await settle(tester);
    expect(find.byType(MongoDocumentsView), findsOneWidget);
    expect(find.textContaining('ann'), findsWidgets);

    // Add a document through the dialog.
    await tester.tap(find.text('Add Document'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(MongoAddDocumentDialog),
        matching: find.byType(material.EditableText),
      ),
      '{"name": "cid", "city": "Rome"}',
    );
    await tester.pump();
    await tester.tap(find.text('Insert Document'));
    await settle(tester);
    expect(mongo.inserted, hasLength(1));
    expect(mongo.inserted.single['name'], 'cid');
    expect(find.textContaining('cid'), findsWidgets);

    // Edit a field of the first document from its expanded card.
    await tester.tap(find.byIcon(material.Icons.expand_more_rounded).first);
    await settle(tester);
    await tester.tap(find.text('name').first);
    await settle(tester);
    await tester.enterText(find.byType(material.EditableText).last, 'annie');
    await tester.pump();
    await tester.tap(find.text('Save to DB'));
    await settle(tester);
    expect(mongo.updates, hasLength(1));
    expect(mongo.updates.single.$1, {'_id': 1});
    expect(mongo.updates.single.$2, {
      r'$set': {'name': 'annie'},
    });

    // Delete it, after confirming.
    await tester.tap(find.byIcon(material.Icons.delete_rounded).first);
    await settle(tester);
    await tester.tap(find.text(
        'I understand that this query cannot be undone and may result in permanent data loss.'));
    await tester.pump();
    await tester.tap(find.text('Execute Destructive Statement'));
    await settle(tester);
    expect(mongo.deletes, [
      {'_id': 1},
    ]);
    expect(find.textContaining('annie'), findsNothing);
  });

  testWidgets('cancelling the delete keeps the document (#1052)',
      timeout: _timeout, (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(queryaThemeTestShell(child: _Explorer(_Connection())));
    await settle(tester);
    await tester.tap(find.text('orders'));
    await settle(tester);

    await tester.tap(find.byIcon(material.Icons.delete_rounded).first);
    await settle(tester);
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(mongo.deletes, isEmpty);
    expect(mongo.docs, hasLength(2));
  });
}
