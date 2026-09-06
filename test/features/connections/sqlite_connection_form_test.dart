import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('showSqliteConnectionForm', () {
    testWidgets('dialog shows SQLite Connection title and controls without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showSqliteConnectionForm(context),
              child: const material.Text('Open SQLite Form'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open SQLite Form'));
      await tester.pumpAndSettle();

      expect(find.text('New SQLite Connection'), findsOneWidget);
      expect(find.text('Connection name'), findsOneWidget);
      expect(find.text('Database file path'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog opens in edit mode when initial connection row is provided',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      final conn = ConnectionRow(
        id: 1,
        name: 'My Cache',
        type: 'sqlite',
        databaseName: '/tmp/test.db',
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () =>
                  showSqliteConnectionForm(context, initial: conn),
              child: const material.Text('Edit SQLite Form'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Edit SQLite Form'));
      await tester.pumpAndSettle();

      expect(find.text('Edit SQLite Connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
