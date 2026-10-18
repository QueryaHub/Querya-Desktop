import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show MaterialApp;
import '../../support/querya_theme_test_shell.dart';
import 'package:querya_desktop/features/mongodb/mongo_database_dialog.dart';

void main() {
  group('showCreateMongoDBDialog', () {
    testWidgets('dialog shows Create Database title and form', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: queryaDarkMaterialTheme,
          darkTheme: queryaDarkMaterialTheme,
          themeMode: material.ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showCreateMongoDBDialog(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Create Database'), findsOneWidget);
      expect(find.text('Database Name'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog and returns null', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: queryaDarkMaterialTheme,
          darkTheme: queryaDarkMaterialTheme,
          themeMode: material.ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showCreateMongoDBDialog(context);
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
  });
}
