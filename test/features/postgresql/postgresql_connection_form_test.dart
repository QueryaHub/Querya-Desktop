import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
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

    testWidgets('Save from URI extracts host and port for display', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      ConnectionRow? result;
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

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'postgresql://user:pass@host:5432/dbname?sslmode=require',
        ),
        'postgresql://u:p@remote.example.com:5433/db',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.host, 'remote.example.com');
      expect(result!.port, 5433);
      expect(result!.name, 'PostgreSQL: remote.example.com:5433');
      expect(result!.connectionString, 'postgresql://u:p@remote.example.com:5433/db');
    });

    testWidgets('SSL certificate path is appended to the URI', (tester) async {
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

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'postgresql://user:pass@host:5432/dbname?sslmode=require',
        ),
        'postgresql://u:p@remote.example.com:5433/db',
      );

      await tester.scrollUntilVisible(
        find.byType(material.Checkbox).first,
        300,
        scrollable: find.byType(material.Scrollable).first,
      );
      await tester.tap(find.byType(material.Checkbox).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('Root CA / SSL Root Certificate')),
        300,
        scrollable: find.byType(material.Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('Root CA / SSL Root Certificate')),
        '/certs/root.pem',
      );
      await tester.pumpAndSettle();

      final uriField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'postgresql://user:pass@host:5432/dbname?sslmode=require',
        ),
      );
      expect(uriField.controller?.text, contains('sslrootcert'));
      expect(uriField.controller?.text, contains('root.pem'));
    });

    testWidgets('Save with SSL certs and no URI builds a connection URI', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      ConnectionRow? result;
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

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'My PostgreSQL Server',
        ),
        'Cert PG',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'localhost',
        ).first,
        'pg.example.com',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'postgres',
        ).first,
        'appdb',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'postgres',
        ).last,
        'admin',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.placeholder is Text && (w.placeholder as Text).data == 'Password',
        ),
        'secret',
      );

      await tester.scrollUntilVisible(
        find.byType(material.Checkbox).first,
        300,
        scrollable: find.byType(material.Scrollable).first,
      );
      await tester.tap(find.byType(material.Checkbox).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('Root CA / SSL Root Certificate')),
        300,
        scrollable: find.byType(material.Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('Root CA / SSL Root Certificate')),
        '/certs/root.pem',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.connectionString, isNotNull);
      expect(result!.connectionString, contains('pg.example.com'));
      expect(result!.connectionString, contains('sslrootcert'));
      expect(result!.connectionString, contains('root.pem'));
      expect(result!.connectionString, contains('admin'));
      expect(result!.connectionString, contains('secret'));
      expect(result!.useSSL, true);
    });
  });
}
