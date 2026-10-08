import 'dart:math' as math;

import 'package:querya_desktop/features/results/charts/chart_data.dart';

/// Colors used by [ChartSvg], as `#rrggbb` strings.
class ChartSvgColors {
  const ChartSvgColors({
    required this.background,
    required this.text,
    required this.grid,
    required this.series,
  });

  final String background;
  final String text;
  final String grid;

  /// Series / slice colors; reused cyclically. The first one draws bars and lines.
  final List<String> series;

  /// `#rrggbb` for a 0xAARRGGBB color value (alpha is dropped).
  static String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Renders a chart as a standalone SVG document, without touching Flutter.
class ChartSvg {
  ChartSvg._();

  static const double width = 960;
  static const double height = 540;
  static const double _left = 64;
  static const double _right = 24;
  static const double _top = 24;
  static const double _bottom = 56;

  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _n(double v) => v.toStringAsFixed(2);

  static String _tick(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  static String build({
    required List<ChartPoint> points,
    required QuickChartType type,
    required ChartSvgColors colors,
    String? title,
  }) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
          'width="${width.toInt()}" height="${height.toInt()}" '
          'viewBox="0 0 ${width.toInt()} ${height.toInt()}" '
          'font-family="sans-serif" font-size="11">');
    if (title != null) b.writeln('<title>${escape(title)}</title>');
    b.writeln('<rect width="100%" height="100%" fill="${colors.background}"/>');
    if (points.isNotEmpty) {
      switch (type) {
        case QuickChartType.bar:
          _axes(b, points, colors, bars: true);
        case QuickChartType.line:
          _axes(b, points, colors, bars: false);
        case QuickChartType.pie:
          _pie(b, points, colors);
      }
    }
    b.writeln('</svg>');
    return b.toString();
  }

  static void _axes(
    StringBuffer b,
    List<ChartPoint> points,
    ChartSvgColors colors, {
    required bool bars,
  }) {
    final plotW = width - _left - _right;
    final plotH = height - _top - _bottom;
    var lo = math.min(0.0, points.map((p) => p.value).reduce(math.min));
    var hi = math.max(0.0, points.map((p) => p.value).reduce(math.max));
    if (hi == lo) hi = lo + 1;
    double y(double v) => _top + plotH - (v - lo) / (hi - lo) * plotH;

    const ticks = 5;
    for (var i = 0; i <= ticks; i++) {
      final v = lo + (hi - lo) * i / ticks;
      final py = y(v);
      b
        ..writeln('<line x1="${_n(_left)}" y1="${_n(py)}" '
            'x2="${_n(width - _right)}" y2="${_n(py)}" '
            'stroke="${colors.grid}" stroke-width="1"/>')
        ..writeln('<text x="${_n(_left - 6)}" y="${_n(py + 4)}" '
            'text-anchor="end" fill="${colors.text}">${escape(_tick(v))}</text>');
    }

    final slot = plotW / points.length;
    final step = (points.length / 8).ceil().clamp(1, 1000);
    final fill = colors.series.first;
    final zero = y(0);
    final line = <String>[];
    for (var i = 0; i < points.length; i++) {
      final cx = _left + slot * (i + 0.5);
      final py = y(points[i].value);
      if (bars) {
        final w = slot * 0.7;
        final top = math.min(py, zero);
        b.writeln('<rect x="${_n(cx - w / 2)}" y="${_n(top)}" '
            'width="${_n(w)}" height="${_n((py - zero).abs())}" '
            'fill="$fill"><title>${escape(points[i].label)}: '
            '${escape(_tick(points[i].value))}</title></rect>');
      } else {
        line.add('${_n(cx)},${_n(py)}');
      }
      if (i % step == 0) {
        b.writeln('<text x="${_n(cx)}" y="${_n(height - _bottom + 18)}" '
            'text-anchor="middle" fill="${colors.text}">'
            '${escape(points[i].label)}</text>');
      }
    }
    if (!bars) {
      b.writeln('<polyline points="${line.join(' ')}" fill="none" '
          'stroke="$fill" stroke-width="2"/>');
      if (points.length <= 50) {
        for (var i = 0; i < points.length; i++) {
          final cx = _left + slot * (i + 0.5);
          b.writeln('<circle cx="${_n(cx)}" cy="${_n(y(points[i].value))}" '
              'r="3" fill="$fill"><title>${escape(points[i].label)}: '
              '${escape(_tick(points[i].value))}</title></circle>');
        }
      }
    }
  }

  static void _pie(
      StringBuffer b, List<ChartPoint> points, ChartSvgColors colors) {
    final total = points.fold<double>(0, (s, p) => s + p.value);
    if (total <= 0) return;
    const cx = 300.0;
    const cy = height / 2;
    const r = 200.0;
    var angle = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final fill = colors.series[i % colors.series.length];
      final sweep = points[i].value / total * 2 * math.pi;
      final tip = '<title>${escape(points[i].label)}: '
          '${escape(_tick(points[i].value))}</title>';
      if (points.length == 1) {
        b.writeln('<circle cx="$cx" cy="$cy" r="$r" fill="$fill">$tip</circle>');
      } else {
        final x1 = cx + r * math.cos(angle);
        final y1 = cy + r * math.sin(angle);
        final x2 = cx + r * math.cos(angle + sweep);
        final y2 = cy + r * math.sin(angle + sweep);
        final large = sweep > math.pi ? 1 : 0;
        b.writeln('<path d="M $cx $cy L ${_n(x1)} ${_n(y1)} '
            'A $r $r 0 $large 1 ${_n(x2)} ${_n(y2)} Z" fill="$fill" '
            'stroke="${colors.background}" stroke-width="1">$tip</path>');
      }
      angle += sweep;
    }
    // Legend.
    final shown = math.min(points.length, 20);
    for (var i = 0; i < shown; i++) {
      final ly = 40.0 + i * 22;
      final fill = colors.series[i % colors.series.length];
      final pct = (points[i].value / total * 100).toStringAsFixed(1);
      b
        ..writeln('<rect x="560" y="${_n(ly - 10)}" width="12" height="12" '
            'fill="$fill"/>')
        ..writeln('<text x="580" y="${_n(ly)}" fill="${colors.text}">'
            '${escape(points[i].label)} ($pct%)</text>');
    }
  }
}
