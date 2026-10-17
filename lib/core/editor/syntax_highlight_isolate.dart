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
  return flattenSpan(span);
}

/// Flattens a nested [TextSpan] into a linear list of [HighlightSegment]s.
List<HighlightSegment> flattenSpan(TextSpan span) {
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

/// Patches cached [oldSegments] to match [newText] while preserving formatting
/// and syntax colors for untouched regions. Used during interactive typing in
/// large documents (>= 8KB) while background isolate highlighting is in flight (#1351).
List<HighlightSegment> patchHighlightSegments({
  required String oldText,
  required List<HighlightSegment> oldSegments,
  required String newText,
}) {
  if (oldText == newText) return oldSegments;
  if (oldSegments.isEmpty) {
    return [HighlightSegment(text: newText)];
  }
  if (newText.isEmpty) {
    return const [];
  }

  var prefixLen = 0;
  final minLen =
      oldText.length < newText.length ? oldText.length : newText.length;
  while (prefixLen < minLen &&
      oldText.codeUnitAt(prefixLen) == newText.codeUnitAt(prefixLen)) {
    prefixLen++;
  }

  var suffixLen = 0;
  final maxSuffix = minLen - prefixLen;
  while (suffixLen < maxSuffix &&
      oldText.codeUnitAt(oldText.length - 1 - suffixLen) ==
          newText.codeUnitAt(newText.length - 1 - suffixLen)) {
    suffixLen++;
  }

  final result = <HighlightSegment>[];
  var offset = 0;

  // 1. Preserve prefix segments.
  for (var i = 0; i < oldSegments.length; i++) {
    final seg = oldSegments[i];
    final segLen = seg.text.length;
    final segStart = offset;
    final segEnd = offset + segLen;
    offset = segEnd;

    if (segStart >= prefixLen) {
      break;
    }
    if (segEnd <= prefixLen) {
      result.add(seg);
    } else {
      final cutLen = prefixLen - segStart;
      if (cutLen > 0) {
        result.add(
          HighlightSegment(
            text: seg.text.substring(0, cutLen),
            colorArgb: seg.colorArgb,
            fontWeightValue: seg.fontWeightValue,
            fontStyleIndex: seg.fontStyleIndex,
          ),
        );
      }
      break;
    }
  }

  // 2. Insert edited middle text.
  final middleLen = (newText.length - suffixLen) - prefixLen;
  if (middleLen > 0) {
    result.add(
      HighlightSegment(
        text: newText.substring(prefixLen, newText.length - suffixLen),
      ),
    );
  }

  // 3. Preserve suffix segments.
  final suffixStart = oldText.length - suffixLen;
  offset = 0;
  for (var i = 0; i < oldSegments.length; i++) {
    final seg = oldSegments[i];
    final segLen = seg.text.length;
    final segStart = offset;
    final segEnd = offset + segLen;
    offset = segEnd;

    if (segEnd <= suffixStart) {
      continue;
    }
    if (segStart >= suffixStart) {
      result.add(seg);
    } else {
      final cutStart = suffixStart - segStart;
      if (cutStart < segLen) {
        result.add(
          HighlightSegment(
            text: seg.text.substring(cutStart),
            colorArgb: seg.colorArgb,
            fontWeightValue: seg.fontWeightValue,
            fontStyleIndex: seg.fontStyleIndex,
          ),
        );
      }
    }
  }

  return result;
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

/// Token styles built for [_cachedBase] (#1543). A theme has a handful of
/// distinct token looks, but a document has hundreds of tokens, and the spans
/// are rebuilt on every keystroke: the styles are made once per base style and
/// shared by every segment that looks the same.
const Object _noBase = Object();
Object? _cachedBase = _noBase;
final Map<int, TextStyle> _tokenStyles = <int, TextStyle>{};
const int _maxTokenStyles = 256;

TextStyle? _styleFromSegment(HighlightSegment s, TextStyle? base) {
  final argb = s.colorArgb;
  final weight = s.fontWeightValue;
  final fontStyle = s.fontStyleIndex;
  if (argb == null && weight == null && fontStyle == null) {
    return null;
  }
  if (!identical(_cachedBase, base)) {
    _cachedBase = base;
    _tokenStyles.clear();
  } else if (_tokenStyles.length >= _maxTokenStyles) {
    _tokenStyles.clear();
  }
  // Colour 32 bits, +1 bit "has a colour", weight 100..900 as 0..9, style as
  // 0 (none) or index + 1.
  final key = (argb ?? 0) |
      ((argb != null ? 1 : 0) << 32) |
      (((weight ?? 0) ~/ 100) << 33) |
      ((fontStyle != null ? fontStyle + 1 : 0) << 37);
  return _tokenStyles[key] ??= (base ?? const TextStyle()).copyWith(
    color: argb != null ? Color(argb) : null,
    fontWeight: _fontWeightFromValue(weight),
    fontStyle: fontStyle != null ? FontStyle.values[fontStyle] : null,
  );
}

/// Runs highlighting on a worker isolate when [job.code] is large enough;
/// otherwise highlights synchronously on the calling isolate (avoids
/// `compute` overhead for small editors).
Future<List<HighlightSegment>> highlightOffMainThread(
  SyntaxHighlightJob job,
) {
  if (job.code.length < kSyntaxHighlightIsolateThreshold) {
    return Future<List<HighlightSegment>>.value(syntaxHighlightInIsolate(job));
  }
  return compute(syntaxHighlightInIsolate, job);
}
