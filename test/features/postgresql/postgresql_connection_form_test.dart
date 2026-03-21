import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  group('showPostgresConnectionForm', () {
    testWidgets('dialog shows PostgreSQL Connection title and main actions',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showPostgresConnectionForm(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('PostgreSQL Connection'), findsOneWidget);
      expect(find.text('Connection URI (optional)'), findsOneWidget);
      expect(find.text('Connection Name'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsAtLeast(1));
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('dialog shows Use SSL/TLS option', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () => showPostgresConnectionForm(context),
              child: const material.Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Use SSL/TLS'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog and returns null', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      dynamic result;
      await tester.pumpWidget(
        ShadcnApp(
          theme: AppTheme.dark,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showPostgresConnectionForm(context);
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
