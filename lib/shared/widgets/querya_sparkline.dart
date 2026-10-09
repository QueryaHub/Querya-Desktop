import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/stats/metric_history.dart';

/// A small line of the last samples of a metric. The tooltip names the latest
/// value and when it was taken. Draws nothing until there are two samples.
class QueryaSparkline extends material.StatelessWidget {
  const QueryaSparkline({
    super.key,
    required this.samples,
    required this.color,
    this.width = 180,
    this.height = 32,
  });

  final List<MetricSample> samples;
  final material.Color color;
  final double width;
  final double height;

  @override
  material.Widget build(material.BuildContext context) {
    final line = material.CustomPaint(
      size: material.Size(width, height),
      painter: _SparklinePainter(samples, color),
    );
    if (samples.isEmpty) return line;
    final last = samples.last;
    final time = last.at.toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    final value = last.value >= 100
        ? last.value.round().toString()
        : last.value.toStringAsFixed(1);
    return material.Tooltip(message: '$value at $hh:$mm:$ss', child: line);
  }
}

class _SparklinePainter extends material.CustomPainter {
  _SparklinePainter(this.samples, this.color);

  final List<MetricSample> samples;
  final material.Color color;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    if (samples.length < 2) return;
    var lo = samples.first.value;
    var hi = samples.first.value;
    for (final s in samples) {
      if (s.value < lo) lo = s.value;
      if (s.value > hi) hi = s.value;
    }
    // A flat series sits in the middle instead of dividing by zero.
    final span = hi == lo ? 1.0 : hi - lo;
    final path = material.Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = hi == lo
          ? size.height / 2
          : size.height - (samples[i].value - lo) / span * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      material.Paint()
        ..color = color
        ..style = material.PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = material.StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.samples != samples || old.color != color;
}
