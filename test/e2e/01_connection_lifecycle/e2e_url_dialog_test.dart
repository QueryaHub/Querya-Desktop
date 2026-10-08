import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/new_connection_url_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

/// The "New connection from URL" modal: paste, see the parsed summary, create.
void main() {
  ConnectionRow? result;
  var closed = false;

  Future<void> open(WidgetTester tester) async {
    result = null;
    closed = false;
    await tester.binding.setSurfaceSize(const material.Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.Center(
            child: material.TextButton(
              onPressed: () async {
                result = await showNewConnectionUrlDialog(context);
                closed = true;
              },
              child: const material.Text('open dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open dialog'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> type(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(material.EditableText), url);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a valid URL shows the parsed type and creates the connection',
      (tester) async {
    await open(tester);
    expect(find.text('New connection from URL'), findsOneWidget);

    await type(tester, 'postgresql://app:s3cret@db.example:5433/shop');
    expect(find.textContaining('POSTGRESQL'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(result, isNotNull);
    expect(result!.type, 'postgresql');
    expect(result!.host, 'db.example');
    expect(result!.port, 5433);
    expect(result!.username, 'app');
    expect(result!.databaseName, 'shop');
  });

  testWidgets('an invalid URL shows an error and keeps the dialog open',
      (tester) async {
    await open(tester);

    await type(tester, 'not a url');
    expect(find.textContaining('POSTGRESQL'), findsNothing);

    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isFalse);
    expect(find.text('New connection from URL'), findsOneWidget);
  });

  testWidgets('an empty field cannot be submitted', (tester) async {
    await open(tester);

    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isFalse);
    expect(find.text('New connection from URL'), findsOneWidget);
  });

  testWidgets('Cancel closes the dialog without a connection', (tester) async {
    await open(tester);

    await type(tester, 'redis://:pw@cache:6380/2');
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(result, isNull);
    expect(find.text('New connection from URL'), findsNothing);
  });
}
