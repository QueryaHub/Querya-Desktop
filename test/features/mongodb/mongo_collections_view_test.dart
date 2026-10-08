import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/features/mongodb/mongo_collections_view.dart';

import '../../support/querya_theme_test_shell.dart';

/// Lists collections from a canned answer, or fails like an unreachable host.
class _FakeMongoConnection extends MongoConnection {
  _FakeMongoConnection({this.collections = const [], this.error})
      : super(id: 7, name: 'fake', host: 'localhost');

  List<String> collections;
  Object? error;
  int listCalls = 0;

  @override
  Future<List<String>> listCollections(String databaseName) async {
    listCalls++;
    if (error != null) throw error!;
    return collections;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeMongoConnection conn, {
  material.ValueChanged<String>? onTap,
  int refreshToken = 0,
}) async {
  await tester.pumpWidget(
    queryaThemeTestShell(
      child: MongoCollectionsView(
        connection: conn,
        database: 'shop',
        onCollectionTap: onTap,
        refreshToken: refreshToken,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('MongoCollectionsView', () {
    testWidgets('lists the collections of the database with a count',
        (tester) async {
      final conn = _FakeMongoConnection(collections: ['users', 'orders']);
      await _pump(tester, conn);

      expect(find.text('shop — Collections (2)'), findsOneWidget);
      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
      expect(conn.listCalls, 1);
    });

    testWidgets('an empty database shows the empty state', (tester) async {
      await _pump(tester, _FakeMongoConnection());

      expect(find.text('shop — Collections (0)'), findsOneWidget);
      expect(find.text('No collections found'), findsOneWidget);
    });

    testWidgets('tapping a row reports the collection name', (tester) async {
      final tapped = <String>[];
      final conn = _FakeMongoConnection(collections: ['users', 'orders']);
      await _pump(tester, conn, onTap: tapped.add);

      await tester.tap(find.text('orders'));
      await tester.pump();

      expect(tapped, ['orders']);
    });

    testWidgets('a failed listing shows the error and Retry reloads',
        (tester) async {
      final conn = _FakeMongoConnection(error: 'connection refused');
      await _pump(tester, conn);

      expect(find.text('Error'), findsOneWidget);
      expect(find.textContaining('connection refused'), findsOneWidget);
      expect(conn.listCalls, 1);

      conn
        ..error = null
        ..collections = [];
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(conn.listCalls, 2);
      expect(find.text('Error'), findsNothing);
      expect(find.text('No collections found'), findsOneWidget);
    });

    testWidgets('a new refresh token lists the collections again',
        (tester) async {
      final conn = _FakeMongoConnection();
      await _pump(tester, conn);
      expect(conn.listCalls, 1);

      conn.collections = [];
      await _pump(tester, conn, refreshToken: 1);

      expect(conn.listCalls, 2);
    });
  });
}
