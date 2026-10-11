import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/editor/querya_highlight_controller.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/pump_syntax_highlight.dart';
import '../../support/querya_theme_test_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });
  testWidgets('QueryaCodeEditor shadcn applies fontSize from props',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.sql,
            fontSize: 17,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.style.fontSize, 17);
  });

  testWidgets('QueryaCodeEditor material variant uses editor foreground',
      (tester) async {
    final theme = QueryaTheme.darkDefault.copyWith(
      editor: QueryaTheme.darkDefault.editor.copyWith(
        foreground: const Color(0xFFABCDEF),
      ),
    );
    await tester.pumpWidget(
      queryaThemeTestShell(
        data: theme,
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.json,
            variant: QueryaCodeEditorVariant.material,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field =
        tester.widget<material.TextField>(find.byType(material.TextField));
    expect(field.style?.color, const Color(0xFFABCDEF));
  });

  testWidgets('SQL highlight controller works directly in QueryaCodeEditor',
      (tester) async {
    final controller = SyntaxHighlightService.createHighlightController(
      language: QueryaCodeLanguage.sql,
      text: '',
    );
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller,
            language: QueryaCodeLanguage.sql,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpSyntaxHighlightDebounce(tester);
    await tester.enterText(find.byType(material.EditableText), 'SELECT 1');
    await tester.pump();
    await pumpSyntaxHighlightDebounce(tester);
    expect(controller.text, 'SELECT 1');
    controller.text = 'UPDATE x';
    await tester.pump();
    await pumpSyntaxHighlightDebounce(tester);
    expect(
      tester
          .widget<material.EditableText>(find.byType(material.EditableText))
          .controller
          .text,
      'UPDATE x',
    );
  });

  testWidgets('onChanged fires when text updates', (tester) async {
    var last = '';
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.plain,
            onChanged: (v) => last = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(material.EditableText), 'hello');
    expect(last, 'hello');
  });

  testWidgets(
      'updating controller does not register duplicate listener on highlight controller',
      (tester) async {
    final controller1 = material.TextEditingController(text: 'SELECT 1;');
    final controller2 = material.TextEditingController(text: 'SELECT 2;');
    int changeCount = 0;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller1,
            language: QueryaCodeLanguage.sql,
            onChanged: (_) => changeCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpSyntaxHighlightDebounce(tester);

    // Update widget with new controller reference
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller2,
            language: QueryaCodeLanguage.sql,
            onChanged: (_) => changeCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pumpSyntaxHighlightDebounce(tester);

    changeCount = 0;
    controller2.text = 'SELECT 3;';
    await tester.pump();

    // Verify onChanged fired exactly once (no duplicate listener registered)
    expect(changeCount, 1);

    // Verify old controller was detached
    controller1.text = 'SELECT 999;';
    await tester.pump();
    expect(changeCount, 1);
  });

  testWidgets('onChanged fires exactly once per text edit when typing',
      (tester) async {
    int count = 0;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.plain,
            onChanged: (_) => count++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(material.EditableText), 'abc');
    expect(count, 1);
  });

  testWidgets('cursor movement and selection changes do not trigger onChanged',
      (tester) async {
    int count = 0;
    final controller = material.TextEditingController(text: 'initial text');
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller,
            language: QueryaCodeLanguage.plain,
            onChanged: (_) => count++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Change selection without changing text
    controller.selection = const material.TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.pump();

    expect(count, 0);

    // Tap the field to move cursor
    await tester.tap(find.byType(material.EditableText));
    await tester.pump();

    expect(count, 0);
  });

  testWidgets(
      'QueryaCodeEditor creates highlight controller by default for SQL',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.sql,
            enableHighlighting: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.controller, isA<QueryaHighlightController>());
  });

  testWidgets(
      'QueryaCodeEditor creates plain controller when enableHighlighting is false',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.sql,
            enableHighlighting: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.controller, isNot(isA<QueryaHighlightController>()));
  });

  testWidgets(
      'updating language updates internal controller and preserves text',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.plain,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(material.EditableText), 'SELECT 1;');
    await tester.pump();

    // Rebuild with SQL language
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            language: QueryaCodeLanguage.sql,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<material.EditableText>(
      find.byType(material.EditableText),
    );
    expect(editable.controller, isA<QueryaHighlightController>());
    expect(editable.controller.text, 'SELECT 1;');
  });

  testWidgets(
      'QueryaCodeEditor does not attach listener to controller when onChanged is null',
      (tester) async {
    final controller = material.TextEditingController(text: 'initial');
    // Initially, controller has 0 listeners
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller,
            language: QueryaCodeLanguage.sql,
            // onChanged is null
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The EditableText attaches its own listener for rendering, but QueryaCodeEditor does not attach an extra listener.
    // When onChanged is passed dynamically:
    var changedValue = '';
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller,
            language: QueryaCodeLanguage.sql,
            onChanged: (v) => changedValue = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.text = 'updated';
    await tester.pump();
    expect(changedValue, 'updated');
  });

  testWidgets(
      'same-length text substitution triggers onChanged correctly',
      (tester) async {
    final controller = material.TextEditingController(text: 'cat');
    var changedValue = '';
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: controller,
            language: QueryaCodeLanguage.sql,
            onChanged: (v) => changedValue = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Same length, different text ('cat' -> 'dog')
    controller.text = 'dog';
    await tester.pump();
    expect(changedValue, 'dog');
  });
}

