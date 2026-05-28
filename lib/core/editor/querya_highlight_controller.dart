import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// [TextEditingController] that applies [Highlighter] in [buildTextSpan].
class QueryaHighlightController extends TextEditingController {
  QueryaHighlightController({
    super.text,
    required this.lightHighlighter,
    required this.darkHighlighter,
  });

  final Highlighter lightHighlighter;
  final Highlighter darkHighlighter;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final highlighter = Theme.of(context).brightness == Brightness.light
        ? lightHighlighter
        : darkHighlighter;
    return TextSpan(
      style: style,
      children: [highlighter.highlight(text)],
    );
  }
}
