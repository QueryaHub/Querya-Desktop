/// Number formatting for chart tooltips and axes.
abstract final class ChartFormat {
  /// Full value for tooltips: no `.0` on integers, thousands separators,
  /// at most two decimals. `1234567` gives `1,234,567`.
  static String full(double v) {
    if (v.isNaN || v.isInfinite) return '$v';
    final abs = v.abs();
    final fixed = abs == abs.roundToDouble()
        ? abs.toStringAsFixed(0)
        : abs.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    final dot = fixed.indexOf('.');
    final whole = dot < 0 ? fixed : fixed.substring(0, dot);
    final frac = dot < 0 ? '' : fixed.substring(dot);
    final sign = v < 0 ? '-' : '';
    return '$sign${_group(whole)}$frac';
  }

  /// Short value for axes: `1234567` gives `1.2M`, `3400` gives `3.4k`.
  static String compact(double v) {
    if (v.isNaN || v.isInfinite) return '$v';
    final abs = v.abs();
    for (final (size, unit) in const [(1e9, 'B'), (1e6, 'M'), (1e3, 'k')]) {
      if (abs >= size) return '${_trimZero((v / size).toStringAsFixed(1))}$unit';
    }
    return full(v);
  }

  static String _group(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static String _trimZero(String s) =>
      s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
