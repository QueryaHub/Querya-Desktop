import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/highlighter_theme_from_querya.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SyntaxHighlightService.ensureInitialized();
  });

  test('highlighterThemeFromQueryaEditor produces SQL spans', () {
    final theme =
        highlighterThemeFromQueryaEditor(QueryaTheme.darkDefault.editor);
    final highlighter = Highlighter(language: 'sql', theme: theme);
    final span = highlighter.highlight('SELECT 1 -- comment');
    expect(span.children, isNotNull);
    expect(span.children!.length, greaterThan(1));
  });

  test('highlighterThemeFromQueryaEditor produces JSON spans', () {
    final theme =
        highlighterThemeFromQueryaEditor(QueryaTheme.darkDefault.editor);
    final highlighter = Highlighter(language: 'json', theme: theme);
    const sample = '{"name": "x", "count": 1, "ok": true, "nil": null}';
    final span = highlighter.highlight(sample);
    expect(span.children, isNotNull);
    expect(span.children!.length, greaterThan(3));
  });
}
