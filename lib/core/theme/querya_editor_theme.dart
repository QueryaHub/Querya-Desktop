import 'dart:ui';

import 'querya_colors.dart';
import 'querya_typography.dart';

/// Syntax and surface tokens for SQL/JSON code editors.
class QueryaEditorTheme {
  const QueryaEditorTheme({
    required this.background,
    required this.foreground,
    required this.lineHighlight,
    required this.selection,
    required this.lineNumber,
    required this.bracketMatch,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.operator,
    required this.function,
    required this.type,
    this.widgetBorder,
    this.fontFamily = QueryaTypography.mono,
    this.fontSize = 13,
  });

  final Color background;
  final Color foreground;
  final Color lineHighlight;
  final Color selection;
  final Color lineNumber;
  final Color bracketMatch;

  /// Chrome border around editor widgets; falls back to workbench [borderSubtle].
  final Color? widgetBorder;
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;
  final Color operator;
  final Color function;
  final Color type;
  final String fontFamily;
  final double fontSize;

  /// Aligned with dark workbench; VS Code Dark+–like token hues.
  static const QueryaEditorTheme darkDefault = QueryaEditorTheme(
    background: QueryaColors.surface,
    foreground: Color(0xFFF8FAFC),
    lineHighlight: Color(0xFF18181B),
    selection: Color(0xFF264F78),
    lineNumber: Color(0xFF858585),
    bracketMatch: Color(0x33006400),
    comment: Color(0xFF6A9955),
    keyword: Color(0xFF569CD6),
    string: Color(0xFFCE9178),
    number: Color(0xFFB5CEA8),
    operator: Color(0xFFD4D4D4),
    function: Color(0xFFDCDCAA),
    type: Color(0xFF4EC9B0),
  );

  static const QueryaEditorTheme lightDefault = QueryaEditorTheme(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF1E293B),
    lineHighlight: Color(0xFFF1F5F9),
    selection: Color(0xFFADD6FF),
    lineNumber: Color(0xFF237893),
    bracketMatch: Color(0x33006400),
    comment: Color(0xFF008000),
    keyword: Color(0xFF0000FF),
    string: Color(0xFFA31515),
    number: Color(0xFF098658),
    operator: Color(0xFF000000),
    function: Color(0xFF795E26),
    type: Color(0xFF267F99),
  );

  QueryaEditorTheme copyWith({
    Color? background,
    Color? foreground,
    Color? lineHighlight,
    Color? selection,
    Color? lineNumber,
    Color? bracketMatch,
    Color? widgetBorder,
    bool clearWidgetBorder = false,
    Color? comment,
    Color? keyword,
    Color? string,
    Color? number,
    Color? operator,
    Color? function,
    Color? type,
    String? fontFamily,
    double? fontSize,
  }) {
    return QueryaEditorTheme(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      lineHighlight: lineHighlight ?? this.lineHighlight,
      selection: selection ?? this.selection,
      lineNumber: lineNumber ?? this.lineNumber,
      bracketMatch: bracketMatch ?? this.bracketMatch,
      widgetBorder:
          clearWidgetBorder ? null : (widgetBorder ?? this.widgetBorder),
      comment: comment ?? this.comment,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      operator: operator ?? this.operator,
      function: function ?? this.function,
      type: type ?? this.type,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  static QueryaEditorTheme lerp(
    QueryaEditorTheme a,
    QueryaEditorTheme b,
    double t,
  ) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return QueryaEditorTheme(
      background: c(a.background, b.background),
      foreground: c(a.foreground, b.foreground),
      lineHighlight: c(a.lineHighlight, b.lineHighlight),
      selection: c(a.selection, b.selection),
      lineNumber: c(a.lineNumber, b.lineNumber),
      bracketMatch: c(a.bracketMatch, b.bracketMatch),
      widgetBorder: t < 0.5 ? a.widgetBorder : b.widgetBorder,
      comment: c(a.comment, b.comment),
      keyword: c(a.keyword, b.keyword),
      string: c(a.string, b.string),
      number: c(a.number, b.number),
      operator: c(a.operator, b.operator),
      function: c(a.function, b.function),
      type: c(a.type, b.type),
      fontFamily: t < 0.5 ? a.fontFamily : b.fontFamily,
      fontSize: a.fontSize + (b.fontSize - a.fontSize) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryaEditorTheme &&
          background == other.background &&
          foreground == other.foreground &&
          lineHighlight == other.lineHighlight &&
          selection == other.selection &&
          lineNumber == other.lineNumber &&
          bracketMatch == other.bracketMatch &&
          widgetBorder == other.widgetBorder &&
          comment == other.comment &&
          keyword == other.keyword &&
          string == other.string &&
          number == other.number &&
          operator == other.operator &&
          function == other.function &&
          type == other.type &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize;

  @override
  int get hashCode => Object.hash(
        background,
        foreground,
        lineHighlight,
        selection,
        lineNumber,
        bracketMatch,
        widgetBorder,
        comment,
        keyword,
        string,
        number,
        operator,
        function,
        type,
        fontFamily,
        fontSize,
      );
}
