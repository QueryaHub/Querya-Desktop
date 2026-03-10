import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/mongodb/mongo_database_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('showCreateMongoDBDialog', () {
    testWidgets('dialog shows Create Database title and form', (tester) async {
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
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
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
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
