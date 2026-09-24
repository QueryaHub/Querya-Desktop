import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/editor/querya_highlight_controller.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_isolate.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/parser/token_colors_highlighter_config.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });

  testWidgets('buildTextSpan ensures span.toPlainText() == text when text changes for > 8KB script',
      (tester) async {
    final pair = SyntaxHighlightService.createPair(
      language: QueryaCodeLanguage.sql,
      queryaTheme: QueryaTheme.darkDefault,
    );
    final lightHighlighter = pair.light;
    final darkHighlighter = pair.dark;
    final lightConfig = buildDefaultEditorHighlighterConfig(
      QueryaTheme.lightDefault.editor,
    );
    final darkConfig = buildDefaultEditorHighlighterConfig(
      QueryaTheme.darkDefault.editor,
    );
    final grammarJson = SyntaxHighlightService.grammarJsonFor(
      QueryaCodeLanguage.sql,
    );

    final initialLargeText = List.filled(500, 'SELECT id FROM users; -- row').join('\n');
    expect(initialLargeText.length, greaterThan(kSyntaxHighlightIsolateThreshold));

    final controller = QueryaHighlightController(
      text: initialLargeText,
      language: QueryaCodeLanguage.sql,
      lightHighlighter: lightHighlighter,
      darkHighlighter: darkHighlighter,
      lightThemeConfig: lightConfig,
      darkThemeConfig: darkConfig,
      grammarJson: grammarJson,
      wrapperColor: Colors.black,
    );

    late BuildContext buildContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (ctx) {
            buildContext = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    // Initial buildTextSpan while isolate is pending
    var span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), initialLargeText);

    // Wait for isolate highlight and debounce to finish
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Now cached span is present
    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), initialLargeText);
    expect(span.children, isNotEmpty);

    // User edits text by adding a character or typing
    final modifiedLargeText = '$initialLargeText\n-- extra line';
    controller.text = modifiedLargeText;

    // Immediately before isolate finishes, buildTextSpan MUST match modifiedLargeText
    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), modifiedLargeText);

    // User deletes characters
    final deletedText = modifiedLargeText.substring(0, modifiedLargeText.length - 20);
    controller.text = deletedText;

    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), deletedText);

    controller.dispose();
  });
}
