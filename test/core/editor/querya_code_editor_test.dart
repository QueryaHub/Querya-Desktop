import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
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
  testWidgets('QueryaCodeEditor shadcn applies fontSize from props', (tester) async {
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

  testWidgets('QueryaCodeEditor material variant uses editor foreground', (tester) async {
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

    final field = tester.widget<material.TextField>(find.byType(material.TextField));
    expect(field.style?.color, const Color(0xFFABCDEF));
  });

  testWidgets('SQL highlighting keeps external controller in sync', (tester) async {
    final external = material.TextEditingController();
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: 400,
          height: 200,
          child: QueryaCodeEditor(
            controller: external,
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
    expect(external.text, 'SELECT 1');
    external.text = 'UPDATE x';
    await tester.pump();
    await pumpSyntaxHighlightDebounce(tester);
    expect(
      tester.widget<material.EditableText>(find.byType(material.EditableText)).controller.text,
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
}
