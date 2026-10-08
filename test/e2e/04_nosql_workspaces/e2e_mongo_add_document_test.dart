import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:querya_desktop/features/mongodb/mongo_add_document_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    void Function(Map<String, dynamic>?) onResult,
  ) async {
    await tester.binding.setSurfaceSize(const material.Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.ElevatedButton(
            onPressed: () async => onResult(
              await showMongoAddDocumentDialog(
                context,
                database: 'shop',
                collection: 'orders',
              ),
            ),
            child: const material.Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a broken draft is rejected, fixing it inserts typed values',
      timeout: _timeout, (tester) async {
    Map<String, dynamic>? result;
    await openDialog(tester, (r) => result = r);

    expect(find.text('Insert a new document into shop.orders.'),
        findsOneWidget);

    await tester.enterText(find.byType(material.EditableText), '{"a": ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert Document'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid EJSON syntax'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byType(material.EditableText),
      '{"_id": {"\$oid": "507f1f77bcf86cd799439011"}, '
      '"placed": {"\$date": "2024-01-15T12:30:00Z"}, '
      '"items": [{"sku": "A1", "qty": 2}]}',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert Document'));
    await tester.pumpAndSettle();

    expect(find.text('Add Document'), findsNothing);
    expect((result!['_id'] as ObjectId).oid, '507f1f77bcf86cd799439011');
    expect(result!['placed'], isA<DateTime>());
    expect((result!['items'] as List).single['qty'], 2);
  });

  testWidgets('Cancel inserts nothing', timeout: _timeout, (tester) async {
    var called = false;
    Map<String, dynamic>? result;
    await openDialog(tester, (r) {
      called = true;
      result = r;
    });

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
  });
}
