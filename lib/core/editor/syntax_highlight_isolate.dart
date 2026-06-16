import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Minimum buffer size before highlighting runs in a background [compute].
const int kSyntaxHighlightIsolateThreshold = 8192;

/// Serializable highlight job for [compute].
class SyntaxHighlightJob {
  const SyntaxHighlightJob({
    required this.code,
    required this.language,
    required this.themeConfigJson,
    required this.grammarJson,
    required this.wrapperArgb,
  });

  final String code;
  final String language;
  final String themeConfigJson;
  final String grammarJson;
  final int wrapperArgb;
}

/// Flat text segment returned from isolate (rebuilt as [TextSpan] on UI thread).
class HighlightSegment {
  const HighlightSegment({
    required this.text,
    this.colorArgb,
    this.fontWeightValue,
    this.fontStyleIndex,
  });

  final String text;
  final int? colorArgb;
  final int? fontWeightValue;
  final int? fontStyleIndex;
}

String? _loadedGrammarLanguage;

/// Top-level entry for [compute]; do not rename (Flutter isolate requirement).
List<HighlightSegment> syntaxHighlightInIsolate(SyntaxHighlightJob job) {
  if (_loadedGrammarLanguage != job.language) {
    Highlighter.addLanguage(job.language, job.grammarJson);
    _loadedGrammarLanguage = job.language;
  }

  final theme = HighlighterTheme.fromConfiguration(
    job.themeConfigJson,
    TextStyle(color: Color(job.wrapperArgb)),
  );
  final highlighter = Highlighter(language: job.language, theme: theme);
  final span = highlighter.highlight(job.code);
  return _flattenSpan(span);
}

List<HighlightSegment> _flattenSpan(TextSpan span) {
  final out = <HighlightSegment>[];
  void walk(TextSpan node) {
    final style = node.style;
    if (node.text != null && node.text!.isNotEmpty) {
      out.add(
        HighlightSegment(
          text: node.text!,
          colorArgb: style?.color?.toARGB32(),
          fontWeightValue: style?.fontWeight?.value,
          fontStyleIndex: style?.fontStyle?.index,
        ),
      );
    }
    if (node.children != null) {
      for (final child in node.children!) {
        if (child is TextSpan) walk(child);
      }
    }
  }

  walk(span);
  return out;
}

TextSpan segmentsToTextSpan(
  List<HighlightSegment> segments, {
  TextStyle? baseStyle,
}) {
  return TextSpan(
    style: baseStyle,
    children: [
      for (final s in segments)
        TextSpan(
          text: s.text,
          style: _styleFromSegment(s, baseStyle),
        ),
    ],
  );
}

FontWeight? _fontWeightFromValue(int? value) {
  if (value == null) return null;
  for (final w in FontWeight.values) {
    if (w.value == value) return w;
  }
  return null;
}

TextStyle? _styleFromSegment(HighlightSegment s, TextStyle? base) {
  if (s.colorArgb == null &&
      s.fontWeightValue == null &&
      s.fontStyleIndex == null) {
    return null;
  }
  return (base ?? const TextStyle()).copyWith(
    color: s.colorArgb != null ? Color(s.colorArgb!) : null,
    fontWeight: _fontWeightFromValue(s.fontWeightValue),
    fontStyle:
        s.fontStyleIndex != null ? FontStyle.values[s.fontStyleIndex!] : null,
  );
}

/// Runs [syntaxHighlightInIsolate] off the UI thread.
Future<List<HighlightSegment>> highlightOffMainThread(
  SyntaxHighlightJob job,
) {
  return compute(syntaxHighlightInIsolate, job);
}
