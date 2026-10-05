import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/features/mongodb/mongo_create_index_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongo_index_info.dart';
import 'package:querya_desktop/features/mongodb/mongo_indexes_view.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  final testConn = MongoConnection(id: 1, name: 'test', host: 'localhost');

  final testIndexes = [
    const MongoIndexInfo(
      name: '_id_',
      keys: {'_id': 1},
      sizeBytes: 16384,
    ),
    const MongoIndexInfo(
      name: 'email_1',
      keys: {'email': 1},
      isUnique: true,
      sizeBytes: 8192,
    ),
    const MongoIndexInfo(
      name: 'createdAt_1',
      keys: {'createdAt': 1},
      expireAfterSeconds: 3600,
      sizeBytes: 4096,
    ),
  ];

  group('MongoIndexesView', () {
    testWidgets('renders index list, metadata badges, keys, and disk sizes',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoIndexesView(
            connection: testConn,
            database: 'testDb',
            collection: 'users',
            initialIndexes: testIndexes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Indexes: users'), findsOneWidget);
      expect(find.text('3 indexes'), findsOneWidget);
      expect(find.text('_id_'), findsOneWidget);
      expect(find.text('email_1'), findsOneWidget);
      expect(find.text('createdAt_1'), findsOneWidget);

      // Badges
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.text('UNIQUE'), findsOneWidget);
      expect(find.text('TTL: 3600s'), findsOneWidget);

      // Sizes
      expect(find.text('16.0 KB'), findsOneWidget);
      expect(find.text('8.0 KB'), findsOneWidget);
      expect(find.text('4.0 KB'), findsOneWidget);
    });

    testWidgets('primary index delete button is disabled with tooltip',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoIndexesView(
            connection: testConn,
            database: 'testDb',
            collection: 'users',
            initialIndexes: testIndexes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tooltipFinder = find.byWidgetPredicate(
        (widget) =>
            widget is material.Tooltip &&
            widget.message == 'Primary index _id_ cannot be deleted',
      );
      expect(tooltipFinder, findsOneWidget);
    });

    testWidgets('calls onBack when back button is tapped', (tester) async {
      var backCalled = false;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoIndexesView(
            connection: testConn,
            database: 'testDb',
            collection: 'users',
            initialIndexes: testIndexes,
            onBack: () => backCalled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to Documents'));
      await tester.pumpAndSettle();

      expect(backCalled, isTrue);
    });

    testWidgets('dropping a custom index shows confirm dialog and drops',
        (tester) async {
      String? droppedIndex;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: MongoIndexesView(
            connection: testConn,
            database: 'testDb',
            collection: 'users',
            initialIndexes: testIndexes,
            onDropIndex: (name) async {
              droppedIndex = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find drop buttons for custom indexes (email_1 and createdAt_1)
      final dropButtons = find.byIcon(material.Icons.delete_outline_rounded);
      expect(dropButtons, findsNWidgets(2));

      await tester.tap(dropButtons.first);
      await tester.pumpAndSettle();

      // Verify QueryaConfirmDialog is displayed
      expect(find.byType(QueryaConfirmDialog), findsOneWidget);
      expect(find.text('Drop Index'), findsWidgets);
      expect(
        find.textContaining('Are you sure you want to drop index "email_1"'),
        findsOneWidget,
      );

      // Confirm drop
      await tester.tap(find.text('Drop Index').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(droppedIndex, equals('email_1'));
    });
  });

  group('MongoCreateIndexDialog', () {
    testWidgets('validates required field name and submits draft',
        (tester) async {
      Map<String, dynamic>? createdKeys;
      bool? isUniqueCreated;
      bool? isSparseCreated;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                await MongoCreateIndexDialog.show(
                  context: context,
                  connection: testConn,
                  database: 'shop',
                  collection: 'orders',
                  onCreateIndex: ({
                    required keys,
                    name,
                    unique = false,
                    sparse = false,
                    expireAfterSeconds,
                  }) async {
                    createdKeys = keys;
                    isUniqueCreated = unique;
                    isSparseCreated = sparse;
                  },
                );
              },
              child: const material.Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Create Index'), findsWidgets);
      expect(find.text('Collection: orders'), findsOneWidget);

      // Initially field name is empty, tap "Create Index" should trigger validation error
      await tester.tap(find.widgetWithText(PrimaryButton, 'Create Index'));
      await tester.pumpAndSettle();

      expect(find.text('All field names must be specified'), findsOneWidget);
      expect(createdKeys, isNull);

      // Enter field name
      final fieldNameInputs = find.byType(material.TextField);
      await tester.enterText(fieldNameInputs.first, 'status');
      await tester.pumpAndSettle();

      // Check unique
      await tester.tap(find.text('Unique'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.widgetWithText(PrimaryButton, 'Create Index'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(createdKeys, equals({'status': 1}));
      expect(isUniqueCreated, isTrue);
      expect(isSparseCreated, isFalse);
    });

    testWidgets('allows adding composite fields and specifying directions',
        (tester) async {
      Map<String, dynamic>? createdKeys;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                await MongoCreateIndexDialog.show(
                  context: context,
                  connection: testConn,
                  database: 'shop',
                  collection: 'orders',
                  onCreateIndex: ({
                    required keys,
                    name,
                    unique = false,
                    sparse = false,
                    expireAfterSeconds,
                  }) async {
                    createdKeys = keys;
                  },
                );
              },
              child: const material.Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // First field: category -> 1
      final textFields = find.byType(material.TextField);
      await tester.enterText(textFields.first, 'category');
      await tester.pumpAndSettle();

      // Add field
      await tester.tap(find.text('Add Field (Compound)'));
      await tester.pumpAndSettle();

      // Second field: price
      final updatedTextFields = find.byType(material.TextField);
      await tester.enterText(updatedTextFields.at(1), 'price');
      await tester.pumpAndSettle();

      // Change direction of second field to Descending (-1)
      final dropdowns = find.byType(QueryaDropdown<dynamic>);
      expect(dropdowns, findsNWidgets(2));
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('-1 (Desc)').last);
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.widgetWithText(PrimaryButton, 'Create Index'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(createdKeys, equals({'category': 1, 'price': -1}));
    });
  });
}
