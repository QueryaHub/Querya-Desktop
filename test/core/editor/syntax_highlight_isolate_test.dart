import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_isolate.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/parser/token_colors_highlighter_config.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });

  test('large SQL buffer highlights off main thread', () async {
    final code = List.filled(500, 'SELECT id FROM users; -- row').join('\n');
    expect(code.length, greaterThan(kSyntaxHighlightIsolateThreshold));

    final config = buildDefaultEditorHighlighterConfig(
      QueryaTheme.darkDefault.editor,
    );
    final segments = await highlightOffMainThread(
      SyntaxHighlightJob(
        code: code,
        language: 'sql',
        themeConfigJson: config,
        grammarJson: SyntaxHighlightService.grammarJsonFor(
          QueryaCodeLanguage.sql,
        ),
        wrapperArgb: QueryaTheme.darkDefault.editor.foreground.toARGB32(),
      ),
    );

    expect(segments, isNotEmpty);
    expect(segments.map((s) => s.text).join(), code);
  });
}
