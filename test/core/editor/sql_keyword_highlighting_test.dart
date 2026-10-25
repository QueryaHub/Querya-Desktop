import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/editor/syntax_highlight_service.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  group('withoutInlineIgnoreCase', () {
    RegExp compile(String p) => RegExp(withoutInlineIgnoreCase(p), multiLine: true);

    test('leaves a pattern without the flag alone', () {
      expect(withoutInlineIgnoreCase(r'\b\d+\b'), r'\b\d+\b');
    });

    test('every alternative matches in any case (Dart applies (?i:a|b) to the '
        'last alternative only)', () {
      final re = compile(r'(?i)\b(select|from|where|order\s+by)\b');
      for (final text in ['select', 'SELECT', 'Select', 'FROM', 'from',
          'WHERE', 'ORDER   BY', 'order by']) {
        expect(re.hasMatch(text), isTrue, reason: text);
      }
      expect(re.hasMatch('selection'), isFalse);
    });

    test('escapes, groups and classes keep their meaning', () {
      final re = compile(r'(?i)(?<!\.)\b(?:p(i|o)_[-a-z0-9_]+)\b');
      expect(re.hasMatch('PI_Value'), isTrue);
      expect(re.hasMatch('po_x-1'), isTrue);
      expect(re.hasMatch('.PI_value'), isFalse);
      expect(compile(r'(?i)[^a-z]x').hasMatch('1X'), isTrue);
      expect(compile(r'(?i)[^a-z]x').hasMatch('aX'), isFalse);
    });
  });

  test('every rule of the shipped SQL grammar compiles after normalisation',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final raw = await rootBundle.loadString(
      'packages/syntax_highlight/grammars/sql.json',
    );
    final fixed = normalizeGrammarJson(raw);
    final rules = <String>[];
    void walk(Object? o) {
      if (o is Map) {
        for (final e in o.entries) {
          if (['match', 'begin', 'end', 'while'].contains(e.key) &&
              e.value is String) {
            rules.add(e.value as String);
          } else {
            walk(e.value);
          }
        }
      } else if (o is List) {
        o.forEach(walk);
      }
    }

    walk(jsonDecode(fixed));
    expect(rules, isNotEmpty);
    for (final rule in rules) {
      expect(() => RegExp(rule, multiLine: true), returnsNormally,
          reason: rule);
    }
  });

  testWidgets('SQL keywords get the keyword colour, in any case',
      (tester) async {
    await SyntaxHighlightService.ensureInitialized();
    final editor = QueryaTheme.darkDefault.editor;
    final highlighter = SyntaxHighlightService.createHighlighter(
      language: QueryaCodeLanguage.sql,
      editorTheme: editor,
      brightness: Brightness.dark,
    );

    final colors = <String, Color?>{};
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        final text = s.text;
        if (text != null && text.trim().isNotEmpty) {
          colors[text.trim()] = s.style?.color;
        }
        s.children?.forEach(walk);
      }
    }

    walk(highlighter.highlight(
        'SELECT a FROM t WHERE b = 1 ORDER BY a;\nselect a from t'));

    for (final word in ['SELECT', 'FROM', 'WHERE', 'ORDER BY', 'select', 'from']) {
      expect(colors[word], editor.keyword, reason: word);
    }
  });
}
