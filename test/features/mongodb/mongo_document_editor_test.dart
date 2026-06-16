import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/mongodb/mongo_document_editor.dart';

import '../../support/pump_syntax_highlight.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });

  final connection = MongoConnection(id: 1, name: 'test', host: 'localhost');

  Future<void> pumpEditor(
    WidgetTester tester, {
    QueryaTheme? theme,
    Map<String, dynamic> document = const {'_id': 'abc', 'a': 1},
  }) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        data: theme ?? QueryaTheme.darkDefault,
        child: material.SizedBox(
          width: 800,
          height: 600,
          child: MongoDocumentEditor(
            connection: connection,
            database: 'db',
            collection: 'items',
            document: document,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpSyntaxHighlightDebounce(tester);
  }

  testWidgets('Format pretty-prints valid JSON', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(
      find.byType(material.EditableText),
      '{"a":1,"b":"x"}',
    );
    await tester.pump();
    await tester.tap(find.text('Format'));
    await tester.pump();
    await pumpSyntaxHighlightDebounce(tester);

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.controller.text, contains('\n'));
    expect(editable.controller.text, contains('  "a"'));
    expect(find.textContaining('Invalid JSON'), findsNothing);
  });

  testWidgets('invalid JSON shows error banner without breaking editor',
      (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(material.EditableText), '{not json');
    await tester.pump();
    await tester.tap(find.text('Format'));
    await tester.pump();
    await pumpSyntaxHighlightDebounce(tester);

    expect(find.textContaining('Invalid JSON'), findsOneWidget);
    expect(find.byType(material.EditableText), findsOneWidget);
  });

  testWidgets('editor uses Querya editor background token', (tester) async {
    const bg = material.Color(0xFF112233);
    final theme = QueryaTheme.darkDefault.copyWith(
      editor: QueryaTheme.darkDefault.editor.copyWith(background: bg),
    );
    await pumpEditor(tester, theme: theme);

    final editorFinder = find.byType(QueryaCodeEditor);
    final container = tester.widget<material.Container>(
      find
          .ancestor(
            of: editorFinder,
            matching: find.byType(material.Container),
          )
          .first,
    );
    expect(container.color, bg);
  });
}
