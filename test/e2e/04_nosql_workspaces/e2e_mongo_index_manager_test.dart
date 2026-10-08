import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/features/mongodb/mongo_index_info.dart';
import 'package:querya_desktop/features/mongodb/mongo_indexes_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final connection = MongoConnection(id: 1, name: 'e2e', host: 'localhost');

  const indexes = [
    MongoIndexInfo(name: '_id_', keys: {'_id': 1}, sizeBytes: 16384),
    MongoIndexInfo(
        name: 'email_1', keys: {'email': 1}, isUnique: true, sizeBytes: 8192),
  ];

  Future<void> open(
    WidgetTester tester, {
    Future<void> Function({
      required Map<String, dynamic> keys,
      String? name,
      bool unique,
      bool sparse,
      int? expireAfterSeconds,
    })? onCreateIndex,
    Future<void> Function(String name)? onDropIndex,
  }) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: MongoIndexesView(
          connection: connection,
          database: 'shop',
          collection: 'orders',
          initialIndexes: indexes,
          onCreateIndex: onCreateIndex,
          onDropIndex: onDropIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Create Index builds a compound index from the indexes tab',
      timeout: _timeout, (tester) async {
    Map<String, dynamic>? created;
    bool? createdUnique;
    await open(
      tester,
      onCreateIndex: ({
        required keys,
        name,
        unique = false,
        sparse = false,
        expireAfterSeconds,
      }) async {
        created = keys;
        createdUnique = unique;
      },
    );

    expect(find.text('Indexes: orders'), findsOneWidget);
    expect(find.text('2 indexes'), findsOneWidget);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Create Index'));
    await tester.pumpAndSettle();
    expect(find.text('Collection: orders'), findsOneWidget);

    await tester.enterText(find.byType(material.TextField).first, 'category');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Field (Compound)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(material.TextField).at(1), 'price');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unique'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Create Index').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    expect(created, {'category': 1, 'price': 1});
    expect(createdUnique, isTrue);
  });

  testWidgets('dropping asks for confirmation and Cancel keeps the index',
      timeout: _timeout, (tester) async {
    String? dropped;
    await open(tester, onDropIndex: (name) async => dropped = name);

    final dropButtons = find.byIcon(material.Icons.delete_outline_rounded);
    expect(dropButtons, findsOneWidget); // `_id_` is not droppable

    await tester.tap(dropButtons);
    await tester.pumpAndSettle();
    expect(find.byType(QueryaConfirmDialog), findsOneWidget);
    expect(
      find.textContaining('Are you sure you want to drop index "email_1"'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dropped, isNull);
    expect(find.text('email_1'), findsOneWidget);
    expect(find.text('2 indexes'), findsOneWidget);
  });
}
