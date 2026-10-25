import 'dart:math' as math;

import 'package:querya_desktop/features/results/charts/chart_axis_labels.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';
import 'package:querya_desktop/features/results/charts/chart_format.dart';

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

  /// Light palette for documents: white background, dark text, and a series
  /// palette that stays readable on white.
  static const ChartSvgColors light = ChartSvgColors(
    background: '#ffffff',
    text: '#334155',
    grid: '#e2e8f0',
    series: ['#2563eb', '#0d9488', '#d97706', '#7c3aed', '#dc2626'],
  );

  static const double width = 960;
  static const double height = 540;
  static const double _left = 64;
  static const double _right = 24;
  static const double _top = 24;
  static const double _fontSize = 11;

  /// Average glyph width in `sans-serif` at [_fontSize], for fitting labels
  /// without a text engine.
  static const double _glyph = _fontSize * 0.58;

  static double _measure(String text) => text.length * _glyph;

  static String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _n(double v) => v.toStringAsFixed(2);


  static String build({
    required List<ChartPoint> points,
    required QuickChartType type,
    required ChartSvgColors colors,
    String? title,
    String? xName,
    String? yName,
  }) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
          'width="${width.toInt()}" height="${height.toInt()}" '
          'viewBox="0 0 ${width.toInt()} ${height.toInt()}" '
          'font-family="sans-serif" font-size="${_fontSize.toInt()}">');
    if (title != null) b.writeln('<title>${escape(title)}</title>');
    b.writeln('<rect width="100%" height="100%" fill="${colors.background}"/>');
    if (points.isNotEmpty) {
      switch (type) {
        case QuickChartType.bar:
          _axes(b, points, colors, bars: true, xName: xName, yName: yName);
        case QuickChartType.line:
          _axes(b, points, colors, bars: false, xName: xName, yName: yName);
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
    String? xName,
    String? yName,
  }) {
    const plotW = width - _left - _right;
    // Line charts on a date X column place points at their real distance and
    // label six dates; the other charts label the points themselves.
    final offsets = bars ? null : ChartData.timeOffsets(points);
    final plan = offsets != null
        ? null
        : ChartAxisLabels.planX(
            labels: [for (final p in points) p.label],
            plotWidth: plotW,
            measure: _measure,
            lineHeight: _fontSize * 1.3,
          );
    final labelsH = plan?.reserved ?? _fontSize * 1.3 + 10;
    final nameH = xName == null ? 0.0 : _fontSize * 1.6;
    final bottom = labelsH + nameH + 8;
    final plotH = height - _top - bottom;
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
            'text-anchor="end" fill="${colors.text}">'
            '${escape(ChartFormat.compact(v))}</text>');
    }

    final slot = plotW / points.length;
    final step = plan?.step ?? 1;
    final fill = colors.series.first;
    final zero = y(0);
    final line = <String>[];
    final spanDays = offsets == null ? 0.0 : offsets.reduce(math.max);
    double xAt(int i) => offsets == null
        ? _left + slot * (i + 0.5)
        : spanDays == 0
            ? _left + plotW / 2
            : _left + plotW * offsets[i] / spanDays;
    final labelY = height - bottom + nameH + 16;
    for (var i = 0; i < points.length; i++) {
      final cx = xAt(i);
      final py = y(points[i].value);
      if (bars) {
        final w = slot * 0.7;
        final top = math.min(py, zero);
        b.writeln('<rect x="${_n(cx - w / 2)}" y="${_n(top)}" '
            'width="${_n(w)}" height="${_n((py - zero).abs())}" '
            'fill="$fill"><title>${escape(points[i].label)}: '
            '${escape(ChartFormat.full(points[i].value))}</title></rect>');
      } else {
        line.add('${_n(cx)},${_n(py)}');
      }
      if (plan != null && i % step == 0) {
        _xLabel(b, points[i].label, cx, labelY - nameH, plan, colors);
      }
    }
    if (offsets != null) {
      // Six dates on the time axis, labelled for the range they cover.
      final origin = ChartData.timeOrigin(points)!;
      final span = ChartData.timeSpan(points);
      for (var k = 0; k <= 6; k++) {
        final at = origin.add(Duration(
            microseconds:
                (spanDays * Duration.microsecondsPerDay * k / 6).round()));
        final x = spanDays == 0 ? _left + plotW / 2 : _left + plotW * k / 6;
        b.writeln('<text x="${_n(x)}" y="${_n(labelY - nameH)}" '
            'text-anchor="middle" fill="${colors.text}">'
            '${escape(ChartData.timeTickLabel(at, span))}</text>');
      }
    }
    if (!bars) {
      b.writeln('<polyline points="${line.join(' ')}" fill="none" '
          'stroke="$fill" stroke-width="2"/>');
      if (points.length <= 50) {
        for (var i = 0; i < points.length; i++) {
          final cx = xAt(i);
          b.writeln('<circle cx="${_n(cx)}" cy="${_n(y(points[i].value))}" '
              'r="3" fill="$fill"><title>${escape(points[i].label)}: '
              '${escape(ChartFormat.full(points[i].value))}</title></circle>');
        }
      }
    }
    if (xName != null) {
      b.writeln('<text x="${_n(_left + plotW / 2)}" y="${_n(height - 8)}" '
          'text-anchor="middle" fill="${colors.text}">${escape(xName)}</text>');
    }
    if (yName != null) {
      final cy = _top + plotH / 2;
      b.writeln('<text x="12" y="${_n(cy)}" text-anchor="middle" '
          'transform="rotate(-90 12 ${_n(cy)})" fill="${colors.text}">'
          '${escape(yName)}</text>');
    }
  }

  /// One X label under the point at [cx], laid out as [plan] says.
  static void _xLabel(
    StringBuffer b,
    String label,
    double cx,
    double baseY,
    XLabelPlan plan,
    ChartSvgColors colors,
  ) {
    switch (plan.layout) {
      case XLabelLayout.horizontal:
        b.writeln('<text x="${_n(cx)}" y="${_n(baseY)}" text-anchor="middle" '
            'fill="${colors.text}">${escape(label)}</text>');
      case XLabelLayout.wrapped:
        final lines = _wrap(label, plan.slot - ChartAxisLabels.gap);
        b.write('<text x="${_n(cx)}" y="${_n(baseY)}" text-anchor="middle" '
            'fill="${colors.text}">');
        for (var l = 0; l < lines.length; l++) {
          b.write('<tspan x="${_n(cx)}" dy="${l == 0 ? 0 : _fontSize * 1.3}">'
              '${escape(lines[l])}</tspan>');
        }
        b.writeln('</text>');
      case XLabelLayout.rotated:
        final cut = ChartAxisLabels.ellipsize(
            label, (plan.labelMaxWidth / _glyph).floor());
        b.writeln('<text x="${_n(cx)}" y="${_n(baseY - 4)}" text-anchor="end" '
            'transform="rotate(-45 ${_n(cx)} ${_n(baseY - 4)})" '
            'fill="${colors.text}">${escape(cut)}</text>');
    }
  }

  /// [text] broken into at most two lines of [room] width, on spaces; the
  /// second line is cut with an ellipsis if it still does not fit.
  static List<String> _wrap(String text, double room) {
    final words = text.split(RegExp(r'\s+'));
    var first = '';
    var i = 0;
    while (i < words.length) {
      final next = first.isEmpty ? words[i] : '$first ${words[i]}';
      if (first.isNotEmpty && _measure(next) > room) break;
      first = next;
      i++;
    }
    final rest = words.sublist(i).join(' ');
    if (rest.isEmpty) return [first];
    return [first, ChartAxisLabels.ellipsize(rest, (room / _glyph).floor())];
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
          '${escape(ChartFormat.full(points[i].value))}</title>';
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
