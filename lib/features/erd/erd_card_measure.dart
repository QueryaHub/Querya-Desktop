import 'package:flutter/painting.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/erd/erd_layout.dart';

/// Measures what a table card shows with the card's own fonts, so the card is
/// exactly as wide as its header and its widest `name  type` row (#1276).
///
/// A glyph-count estimate was short for real fonts and the type was cut.
class ErdCardMeasure {
  ErdCardMeasure({required TextStyle base, TextScaler? textScaler})
      : _base = base,
        _scaler = textScaler ?? TextScaler.noScaling;

  final TextStyle _base;
  final TextScaler _scaler;
  final _cache = <String, double>{};

  double _text(String text, TextStyle style) {
    final key = '${style.fontSize}|${style.fontWeight}|${style.fontFamily}|$text';
    return _cache.putIfAbsent(key, () {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    });
  }

  static const _header =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const _count = TextStyle(fontSize: 10);
  static const _name = TextStyle(fontSize: 12);
  static const _pkName = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const _type = TextStyle(
    fontSize: 10,
    fontFamily: QueryaTypography.mono,
    fontFamilyFallback: QueryaTypography.monoFontFamilyFallback,
  );

  /// Card width: the card's paddings and slots (as `_TableCard` lays them out)
  /// plus the measured text, between [ErdLayout.minCardWidth] and
  /// [ErdLayout.maxCardWidth].
  double width(ErdTable t) {
    // Padding 10, icon 14, gap 6, name, gap 8, count, padding 10, border 2.
    var w = 50 + _text(t.name, _header) + _text('${t.columns.length}', _count);
    for (final c in t.columns) {
      final type = c.isNullable ? '${c.type}?' : c.type;
      // Padding 10, marker slot 26, name, gap 8, type, padding 10, border 2.
      // Plus 4 px so sub-pixel rounding never ellipsizes.
      final row = 60 +
          _text(c.name, c.isPrimaryKey ? _pkName : _name) +
          _text(type, _type);
      if (row > w) w = row;
    }
    return w
        .clamp(ErdLayout.minCardWidth, ErdLayout.maxCardWidth)
        .ceilToDouble();
  }
}
