import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/features/connections/forms/connection_auth_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_database_section.dart';
import 'package:querya_desktop/features/connections/forms/connection_host_port_section.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  Widget buildApp(Widget child) {
    return ShadcnApp(
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: material.Scaffold(
        body: material.SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  group('ConnectionHostPortSection', () {
    testWidgets('renders Host and Port fields with custom labels and values',
        (tester) async {
      final hostController = material.TextEditingController(text: '127.0.0.1');
      final portController = material.TextEditingController(text: '5432');

      await tester.pumpWidget(
        buildApp(
          ConnectionHostPortSection(
            hostController: hostController,
            portController: portController,
            portPlaceholder: '5432',
          ),
        ),
      );

      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('127.0.0.1'), findsOneWidget);
      expect(find.text('5432'), findsOneWidget);
    });
  });

  group('ConnectionDatabaseSection', () {
    testWidgets('renders database field with label and placeholder',
        (tester) async {
      final dbController = material.TextEditingController(text: 'my_db');

      await tester.pumpWidget(
        buildApp(
          ConnectionDatabaseSection(
            databaseController: dbController,
            label: 'Database name',
            placeholder: 'postgres',
          ),
        ),
      );

      expect(find.text('Database name'), findsOneWidget);
      expect(find.text('my_db'), findsOneWidget);
    });
  });

  group('ConnectionAuthSection', () {
    testWidgets('toggles password visibility when eye icon is clicked',
        (tester) async {
      final userController = material.TextEditingController(text: 'admin');
      final passController = material.TextEditingController(text: 'secret');

      await tester.pumpWidget(
        buildApp(
          ConnectionAuthSection(
            usernameController: userController,
            passwordController: passController,
            useRowLayout: false,
          ),
        ),
      );

      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byIcon(material.Icons.visibility), findsOneWidget);

      await tester.tap(find.byIcon(material.Icons.visibility));
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.visibility_off), findsOneWidget);
    });

    testWidgets('renders in row layout and shows remove saved password when editing',
        (tester) async {
      final userController = material.TextEditingController(text: 'admin');
      final passController = material.TextEditingController();
      bool removePassword = false;

      await tester.pumpWidget(
        buildApp(
          ConnectionAuthSection(
            usernameController: userController,
            passwordController: passController,
            isEditing: true,
            removeSavedPassword: removePassword,
            onRemoveSavedPasswordChanged: (v) => removePassword = v,
            useRowLayout: true,
          ),
        ),
      );

      expect(find.text('Remove saved password on save'), findsOneWidget);
      expect(find.text('Leave blank to keep existing'), findsOneWidget);
    });
  });
}
