import 'package:flutter/painting.dart';
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

  test('small SQL buffer highlights inline below isolate threshold', () async {
    const code = 'SELECT 1;';
    expect(code.length, lessThan(kSyntaxHighlightIsolateThreshold));

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

  group('segmentsToTextSpan style sharing (#1543)', () {
    const keyword = HighlightSegment(
      text: 'SELECT',
      colorArgb: 0xFF2196F3,
      fontWeightValue: 700,
    );
    const keywordAgain = HighlightSegment(
      text: 'FROM',
      colorArgb: 0xFF2196F3,
      fontWeightValue: 700,
    );
    const comment = HighlightSegment(
      text: '-- x',
      colorArgb: 0xFF808080,
      fontStyleIndex: 1,
    );
    const plain = HighlightSegment(text: ' ');

    TextStyle? styleOf(TextSpan span, int i) =>
        (span.children![i] as TextSpan).style;

    test('segments that look the same share one TextStyle', () {
      const base = TextStyle(fontSize: 14);
      final span = segmentsToTextSpan(
        [keyword, plain, keywordAgain, comment],
        baseStyle: base,
      );
      expect(identical(styleOf(span, 0), styleOf(span, 2)), isTrue);
      expect(identical(styleOf(span, 0), styleOf(span, 3)), isFalse);
      expect(styleOf(span, 1), isNull); // no colour, weight or style
    });

    test('styles keep the base style and the segment attributes', () {
      const base = TextStyle(fontSize: 14);
      final span = segmentsToTextSpan([keyword, comment], baseStyle: base);
      final kw = styleOf(span, 0)!;
      expect(kw.fontSize, 14);
      expect(kw.color, const Color(0xFF2196F3));
      expect(kw.fontWeight, FontWeight.w700);
      expect(kw.fontStyle, isNull);
      final cm = styleOf(span, 1)!;
      expect(cm.color, const Color(0xFF808080));
      expect(cm.fontStyle, FontStyle.italic);
      expect(cm.fontWeight, isNull);
    });

    test('a different base style is not served the old styles', () {
      final a = segmentsToTextSpan([keyword], baseStyle: const TextStyle(fontSize: 12));
      final b = segmentsToTextSpan([keyword], baseStyle: const TextStyle(fontSize: 18));
      expect(styleOf(a, 0)!.fontSize, 12);
      expect(styleOf(b, 0)!.fontSize, 18);
    });

    test('a null base style works and more looks than the cache holds do not break',
        () {
      final segments = [
        for (var i = 0; i < 600; i++)
          HighlightSegment(text: 't', colorArgb: 0xFF000000 + i),
      ];
      final span = segmentsToTextSpan(segments);
      for (var i = 0; i < segments.length; i++) {
        expect(styleOf(span, i)!.color, Color(0xFF000000 + i));
      }
    });
  });
}
