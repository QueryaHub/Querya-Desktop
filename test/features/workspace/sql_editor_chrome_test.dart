import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_from_vscode.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_workbench_theme.dart';
import 'package:querya_desktop/features/workspace/sql_editor_chrome.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('SqlEditorChrome.inlineFieldDecoration', () {
    test('uses editor background and workbench accent glow (dialog fields)', () {
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
    testWidgets('applies imported editor background and border',
        (tester) async {
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
      final border =
          (inner.decoration! as material.BoxDecoration).border as Border;
      expect(
        border.top.color,
        const Color(0xFF112233).withValues(alpha: 0.5),
      );

      // No glow: one framed card (#1558).
      final shadows = containers
          .map((c) => c.decoration)
          .whereType<material.BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <material.BoxShadow>[]);
      expect(shadows, isEmpty);
    });

    testWidgets('the border takes the accent while the editor has the keyboard',
        (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.darkDefault,
          child: material.SizedBox(
            width: 320,
            height: 200,
            child: SqlEditorChrome(
              child: Focus(focusNode: focus, child: const material.SizedBox.expand()),
            ),
          ),
        ),
      );

      Color borderColor() {
        final c = tester.widgetList<material.Container>(find.descendant(
          of: find.byType(SqlEditorChrome),
          matching: find.byType(material.Container),
        )).firstWhere((c) => c.decoration is material.BoxDecoration &&
            (c.decoration! as material.BoxDecoration).border != null);
        return ((c.decoration! as material.BoxDecoration).border! as Border)
            .top
            .color;
      }

      final idle = borderColor();
      focus.requestFocus();
      await tester.pump();
      final focused = borderColor();
      expect(focused,
          QueryaTheme.darkDefault.workbench.accent.withValues(alpha: 0.6));
      expect(idle, isNot(focused));
    });

    testWidgets('a card with nothing to type in keeps its border', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.darkDefault,
          child: material.SizedBox(
            width: 320,
            height: 200,
            child: SqlEditorChrome(
              showFocus: false,
              background: const Color(0xFF123456),
              child: Focus(focusNode: focus, child: const material.SizedBox.expand()),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      final c = tester.widgetList<material.Container>(find.descendant(
        of: find.byType(SqlEditorChrome),
        matching: find.byType(material.Container),
      )).firstWhere((c) => c.decoration is material.BoxDecoration &&
          (c.decoration! as material.BoxDecoration).border != null);
      final d = c.decoration! as material.BoxDecoration;
      expect(d.color, const Color(0xFF123456));
      expect(
        (d.border! as Border).top.color,
        isNot(QueryaTheme.darkDefault.workbench.accent.withValues(alpha: 0.6)),
      );
    });
  });

  group('SqlEditorChrome.sqlToolbarDecoration', () {
    testWidgets('uses solid surface and subtle border in dark theme',
        (tester) async {
      late material.BoxDecoration deco;
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.darkDefault,
          child: material.Builder(
            builder: (context) {
              deco = SqlEditorChrome.sqlToolbarDecoration(context);
              return const material.SizedBox.shrink();
            },
          ),
        ),
      );
      expect(deco.color, QueryaTheme.darkDefault.workbench.surface);
      final border = deco.border as Border?;
      expect(
        border?.bottom.color,
        QueryaTheme.darkDefault.workbench.borderSubtle
            .withValues(alpha: 0.35),
      );
    });

    testWidgets('uses solid surface and subtle border in light theme',
        (tester) async {
      late material.BoxDecoration deco;
      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.lightDefault,
          child: material.Builder(
            builder: (context) {
              deco = SqlEditorChrome.sqlToolbarDecoration(context);
              return const material.SizedBox.shrink();
            },
          ),
        ),
      );
      expect(deco.color, QueryaTheme.lightDefault.workbench.surface);
      final border = deco.border as Border?;
      expect(
        border?.bottom.color,
        QueryaTheme.lightDefault.workbench.borderSubtle
            .withValues(alpha: 0.35),
      );
    });
  });
}
