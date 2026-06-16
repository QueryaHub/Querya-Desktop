import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/highlighter_theme_from_querya.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Highlighter.initialize(['sql']);
  });

  test('Dracula-like tokenColors distinguish comment, keyword, string in SQL',
      () {
    final raw =
        File('test/fixtures/themes/dracula_tokens.json').readAsStringSync();
    final manifest = VsCodeThemeManifest.fromJsonString(raw);
    final theme = highlighterThemeFromQueryaEditor(
      QueryaTheme.darkDefault.editor,
      tokenColors: manifest.tokenColors,
    );
    final highlighter = Highlighter(language: 'sql', theme: theme);
    const sql = 'SELECT 1 -- note\n\'hello\'';
    final span = highlighter.highlight(sql);
    final colors = _collectColors(span);
    expect(colors.length, greaterThanOrEqualTo(3));
    expect(colors.toSet().length, greaterThanOrEqualTo(3));
  });
}

Set<Color> _collectColors(TextSpan span) {
  final colors = <Color>{};
  void walk(TextSpan node) {
    final c = node.style?.color;
    if (c != null) colors.add(c);
    if (node.children != null) {
      for (final child in node.children!) {
        if (child is TextSpan) walk(child);
      }
    }
  }

  walk(span);
  return colors;
}
