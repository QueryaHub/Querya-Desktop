import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/features/mongodb/mongo_document_editor.dart';

import '../../support/pump_syntax_highlight.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });

  tearDown(UnsavedWorkRegistry.instance.resetForTest);

  final connection = MongoConnection(id: 1, name: 'test', host: 'localhost');

  Future<void> pumpEditor(
    WidgetTester tester, {
    QueryaTheme? theme,
    Map<String, dynamic> document = const {'_id': 'abc', 'a': 1},
    material.VoidCallback? onBack,
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
            onBack: onBack,
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

  testWidgets('Delete Cancel does not call onDocumentDeleted', (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(800, 700));
    var deleted = false;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 800,
          height: 700,
          child: MongoDocumentEditor(
            connection: connection,
            database: 'db',
            collection: 'items',
            document: const {'_id': 'abc', 'a': 1},
            onDocumentDeleted: () => deleted = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpSyntaxHighlightDebounce(tester);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('DELETE DOCUMENT'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('clean Back leaves the editor without a confirm dialog',
      (tester) async {
    var wentBack = false;
    await pumpEditor(tester, onBack: () => wentBack = true);
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isFalse);

    await tester.tap(find.byIcon(material.Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(wentBack, isTrue);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('dirty Back Cancel keeps edits; Discard calls onBack',
      (tester) async {
    await tester.binding.setSurfaceSize(const material.Size(800, 700));
    var wentBack = false;
    await pumpEditor(tester, onBack: () => wentBack = true);

    await tester.enterText(find.byType(material.EditableText), '{"a":2}');
    await tester.pump();
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);

    await tester.tap(find.byIcon(material.Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(wentBack, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(wentBack, isFalse);
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isTrue);

    await tester.tap(find.byIcon(material.Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    await tester.pumpWidget(
      queryaThemeTestShell(child: const material.SizedBox()),
    );
    expect(UnsavedWorkRegistry.instance.hasUnsaved, isFalse);
  });
}
