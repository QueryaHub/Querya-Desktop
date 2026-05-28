import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
      );
      final border = deco.border as Border;
      expect(border.top.color, const Color(0xFFFF0000).withValues(alpha: 0.45));
    });
  });
}
