import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('SqlEditorChrome.inlineFieldDecoration', () {
    test('uses editor background and workbench accent glow', () {
      const editor = QueryaEditorTheme(
        background: Color(0xFF111111),
        foreground: Color(0xFFFFFFFF),
        lineHighlight: Color(0xFF000000),
        selection: Color(0xFF222222),
        lineNumber: Color(0xFF333333),
        bracketMatch: Color(0xFF444444),
        comment: Color(0xFF555555),
        keyword: Color(0xFF666666),
        string: Color(0xFF777777),
        number: Color(0xFF888888),
        operator: Color(0xFF999999),
        function: Color(0xFFAAAAAA),
        type: Color(0xFFBBBBBB),
      );
      const workbench = QueryaWorkbenchTheme(
        canvas: Color(0xFF000000),
        surface: Color(0xFF000001),
        sidebarBackground: Color(0xFF000002),
        editorBackground: Color(0xFF111111),
        borderSubtle: Color(0xFFCCCCCC),
        accent: Color(0xFF00FFFF),
        onAccent: Color(0xFF000000),
        mutedForeground: Color(0xFF888888),
        destructive: Color(0xFFFF0000),
        success: Color(0xFF00FF00),
        warning: Color(0xFFFFFF00),
        gitModified: Color(0xFFFF8800),
        gitUntracked: Color(0xFF00FF88),
      );

      final deco = SqlEditorChrome.inlineFieldDecoration(editor, workbench);
      expect(deco.color, const Color(0xFF111111));
      expect(
        deco.boxShadow!.single.color,
        const Color(0xFF00FFFF).withValues(alpha: 0.07),
      );
    });

    test('widgetBorder overrides workbench border', () {
      const editor = QueryaEditorTheme(
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF000000),
        lineHighlight: Color(0xFFF0F0F0),
        selection: Color(0xFFADD6FF),
        lineNumber: Color(0xFF237893),
        bracketMatch: Color(0x33006400),
        widgetBorder: Color(0xFFFF0000),
        comment: Color(0xFF008000),
        keyword: Color(0xFF0000FF),
        string: Color(0xFFA31515),
        number: Color(0xFF098658),
        operator: Color(0xFF000000),
        function: Color(0xFF795E26),
        type: Color(0xFF267F99),
      );
      final deco = SqlEditorChrome.inlineFieldDecoration(
        editor,
        QueryaWorkbenchTheme.lightDefault,
        brightness: Brightness.light,
      );
      final border = deco.border as Border;
      expect(border.top.color, const Color(0xFFFF0000).withValues(alpha: 0.45));
      expect(
        deco.boxShadow!.single.color,
        QueryaWorkbenchTheme.lightDefault.accent.withValues(alpha: 0.05),
      );
    });
  });

  group('SqlEditorChrome widget', () {
    testWidgets('applies imported editor background and border', (tester) async {
      final queryaTheme = buildQueryaThemeFromVsCodeColors(
        brightness: Brightness.dark,
        colors: const {
          'editor.background': '#aabbcc',
          'editorWidget.border': '#112233',
          'focusBorder': '#00ffee',
        },
        fallback: QueryaTheme.darkDefault,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          data: queryaTheme,
          child: const material.SizedBox(
            width: 320,
            height: 200,
            child: SqlEditorChrome(
              child: material.SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<material.Container>(
        find.descendant(
          of: find.byType(SqlEditorChrome),
          matching: find.byType(material.Container),
        ),
      );

      final inner = containers.firstWhere((c) {
        final d = c.decoration;
        return d is material.BoxDecoration &&
            d.color == const Color(0xFFAABBCC);
      });
      final border = (inner.decoration! as material.BoxDecoration).border as Border;
      expect(
        border.top.color,
        const Color(0xFF112233).withValues(alpha: 0.5),
      );

      final outerGlow = containers
          .map((c) => c.decoration)
          .whereType<material.BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <material.BoxShadow>[])
          .map((s) => s.color)
          .whereType<Color>()
          .firstWhere((c) => c == const Color(0xFF00FFEE).withValues(alpha: 0.1));
      expect(outerGlow, const Color(0xFF00FFEE).withValues(alpha: 0.1));
    });
  });
}
