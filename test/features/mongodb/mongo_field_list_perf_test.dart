import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mongodb/mongo_documents_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('MongoFieldList virtualization and layout optimization', () {
    testWidgets('renders lightweight Column and no ListView when <= 10 fields',
        (tester) async {
      final doc = {
        '_id': '64b1f2a3c9e77a1234567890',
        'title': 'Test Item',
        'count': 42,
        'active': true,
      };

      String? inspectedKey;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) {
              final scs = shadcn.Theme.of(context).colorScheme;
              return material.Scaffold(
                body: MongoFieldList(
                  document: doc,
                  colorScheme: scs,
                  shadcnCs: scs,
                  onInspectField: (k) => inspectedKey = k,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render as Column to eliminate scrollable/shrinkWrap overhead
      expect(find.byType(material.Column), findsOneWidget);
      expect(find.byType(material.ListView), findsNothing);

      // Verify fields are present
      expect(find.text('title'), findsOneWidget);
      expect(find.text('Test Item'), findsOneWidget);

      // Inspecting field
      await tester.tap(find.text('title'));
      await tester.pumpAndSettle();
      expect(inspectedKey, 'title');
    });

    testWidgets('renders virtualized ListView without shrinkWrap when > 10 fields',
        (tester) async {
      // 15 fields
      final doc = <String, dynamic>{
        '_id': '64b1f2a3c9e77a1234567890',
      };
      for (var i = 1; i <= 14; i++) {
        doc['field_$i'] = 'value_$i';
      }

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) {
              final scs = shadcn.Theme.of(context).colorScheme;
              return material.Scaffold(
                body: MongoFieldList(
                  document: doc,
                  colorScheme: scs,
                  shadcnCs: scs,
                  onInspectField: (_) {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Must render ListView without shrinkWrap
      final listViewFinder = find.byType(material.ListView);
      expect(listViewFinder, findsOneWidget);

      final listView = tester.widget<material.ListView>(listViewFinder);
      expect(listView.shrinkWrap, isFalse);
    });
  });
}
