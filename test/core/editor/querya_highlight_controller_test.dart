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

    // 1. Initialize controller with small text (< threshold) to populate _cachedSpan synchronously
    const smallText = 'SELECT id FROM users;';
    final controller = QueryaHighlightController(
      text: smallText,
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

    // Initial highlight for small text populates _cachedSpan
    var span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), smallText);
    expect(span.children, isNotNull);

    // 2. Switch to large text (> 8KB). Stale _cachedSpan from smallText must NOT be returned.
    final largeText = List.filled(500, 'SELECT id FROM users; -- row').join('\n');
    expect(largeText.length, greaterThan(kSyntaxHighlightIsolateThreshold));
    controller.text = largeText;

    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    // span.toPlainText() MUST match largeText, never stale smallText
    expect(span.toPlainText(), largeText);
    expect(span.toPlainText() == controller.text, isTrue);

    // 3. User edits text while isolate highlight is pending (typing characters)
    final modifiedLargeText = '$largeText\n-- extra query';
    controller.text = modifiedLargeText;

    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), modifiedLargeText);
    expect(span.toPlainText() == controller.text, isTrue);

    // 4. User deletes characters
    final deletedText = modifiedLargeText.substring(0, modifiedLargeText.length - 25);
    controller.text = deletedText;

    span = controller.buildTextSpan(
      context: buildContext,
      withComposing: false,
    );
    expect(span.toPlainText(), deletedText);
    expect(span.toPlainText() == controller.text, isTrue);

    controller.dispose();
  });
}
