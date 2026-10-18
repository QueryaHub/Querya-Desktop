import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_text_field.dart';

/// A colour picker (#1734, epic #1465): a saturation / brightness area, hue
/// and alpha bars, and a hex field (`#RRGGBB` or `#AARRGGBB`).
class QueryaColorPicker extends material.StatefulWidget {
  const QueryaColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.alpha = true,
  });

  final material.Color value;
  final material.ValueChanged<material.Color> onChanged;

  /// Whether the alpha bar and the `AA` of the hex are offered.
  final bool alpha;

  /// `#RRGGBB`, or `#AARRGGBB` with [alpha].
  static String toHex(material.Color c, {bool alpha = true}) {
    String h(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${alpha ? h(c.a) : ''}${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
  }

  /// The colour of `RRGGBB`, `#RRGGBB`, `AARRGGBB` or `#AARRGGBB`; null when
  /// it is not one of them.
  static material.Color? parseHex(String text) {
    final t = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(t)) return null;
    final v = int.parse(t, radix: 16);
    return material.Color(t.length == 6 ? 0xFF000000 | v : v);
  }

  @override
  material.State<QueryaColorPicker> createState() => _QueryaColorPickerState();
}

class _QueryaColorPickerState extends material.State<QueryaColorPicker> {
  late material.HSVColor _hsv;
  late final material.TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = material.HSVColor.fromColor(widget.value);
    _hex = material.TextEditingController(
        text: QueryaColorPicker.toHex(widget.value, alpha: widget.alpha));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(material.HSVColor next) {
    setState(() => _hsv = next);
    final c = next.toColor();
    _hex.text = QueryaColorPicker.toHex(c, alpha: widget.alpha);
    widget.onChanged(c);
  }

  void _typed(String text) {
    final c = QueryaColorPicker.parseHex(text);
    if (c == null) return;
    setState(() => _hsv = material.HSVColor.fromColor(c));
    widget.onChanged(c);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    final hueColor = material.HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    final opaque = _hsv.withAlpha(1).toColor();
    return material.Column(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.SizedBox(
          height: 160,
          child: _Drag(
            onPosition: (p) => _set(_hsv
                .withSaturation(p.dx.clamp(0, 1))
                .withValue(1 - p.dy.clamp(0, 1))),
            child: material.CustomPaint(
              painter: _SvPainter(hueColor, _hsv.saturation, _hsv.value,
                  cs.foreground),
            ),
          ),
        ),
        const material.SizedBox(height: 12),
        _Bar(
          height: 14,
          position: _hsv.hue / 360,
          onPosition: (v) => _set(_hsv.withHue((v * 360).clamp(0, 359.999))),
          gradient: material.LinearGradient(colors: [
            for (var i = 0; i <= 6; i++)
              material.HSVColor.fromAHSV(1, i * 60, 1, 1).toColor(),
          ]),
          thumb: hueColor,
        ),
        if (widget.alpha) ...[
          const material.SizedBox(height: 10),
          _Bar(
            height: 14,
            position: _hsv.alpha,
            onPosition: (v) => _set(_hsv.withAlpha(v.clamp(0, 1))),
            gradient: material.LinearGradient(
                colors: [opaque.withValues(alpha: 0), opaque]),
            thumb: _hsv.toColor(),
            checkered: true,
          ),
        ],
        const material.SizedBox(height: 12),
        material.Row(
          children: [
            material.Container(
              width: 32,
              height: 32,
              decoration: material.BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: material.BorderRadius.circular(6),
                border: material.Border.all(color: cs.border),
              ),
            ),
            const material.SizedBox(width: 10),
            material.Expanded(
              child: QueryaTextField(
                controller: _hex,
                onChanged: _typed,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(9),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reports the pointer as a 0–1 position in its box while pressed or dragged.
class _Drag extends material.StatelessWidget {
  const _Drag({required this.child, required this.onPosition});

  final material.Widget child;
  final material.ValueChanged<material.Offset> onPosition;

  @override
  material.Widget build(material.BuildContext context) {
    return material.LayoutBuilder(builder: (context, box) {
      void at(material.Offset local) => onPosition(material.Offset(
            (local.dx / box.maxWidth).clamp(0, 1),
            (local.dy / box.maxHeight).clamp(0, 1),
          ));
      return material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onPanDown: (d) => at(d.localPosition),
        onPanUpdate: (d) => at(d.localPosition),
        child: material.ClipRRect(
          borderRadius: material.BorderRadius.circular(6),
          child: child,
        ),
      );
    });
  }
}

class _Bar extends material.StatelessWidget {
  const _Bar({
    required this.height,
    required this.position,
    required this.onPosition,
    required this.gradient,
    required this.thumb,
    this.checkered = false,
  });

  final double height;
  final double position;
  final material.ValueChanged<double> onPosition;
  final material.Gradient gradient;
  final material.Color thumb;
  final bool checkered;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = context.colors;
    return material.SizedBox(
      height: height + 8,
      child: material.LayoutBuilder(builder: (context, box) {
        final x = position.clamp(0, 1) * box.maxWidth;
        return material.GestureDetector(
          behavior: material.HitTestBehavior.opaque,
          onPanDown: (d) => onPosition(d.localPosition.dx / box.maxWidth),
          onPanUpdate: (d) => onPosition(d.localPosition.dx / box.maxWidth),
          child: material.Stack(
            clipBehavior: material.Clip.none,
            alignment: material.Alignment.centerLeft,
            children: [
              material.Positioned.fill(
                top: 4,
                bottom: 4,
                child: material.ClipRRect(
                  borderRadius: material.BorderRadius.circular(height / 2),
                  child: material.Stack(fit: material.StackFit.expand, children: [
                    if (checkered)
                      material.CustomPaint(painter: _Checkers(cs.border)),
                    material.DecoratedBox(
                        decoration: material.BoxDecoration(gradient: gradient)),
                  ]),
                ),
              ),
              material.Positioned(
                left: x - 9,
                child: material.Container(
                  width: 18,
                  height: 18,
                  decoration: material.BoxDecoration(
                    color: thumb,
                    shape: material.BoxShape.circle,
                    border: material.Border.all(color: cs.foreground, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SvPainter extends material.CustomPainter {
  _SvPainter(this.hue, this.s, this.v, this.ring);

  final material.Color hue;
  final double s;
  final double v;
  final material.Color ring;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final rect = material.Offset.zero & size;
    canvas.drawRect(
        rect,
        material.Paint()
          ..shader = material.LinearGradient(
            colors: [material.Colors.white, hue],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        material.Paint()
          ..shader = const material.LinearGradient(
            begin: material.Alignment.topCenter,
            end: material.Alignment.bottomCenter,
            colors: [material.Color(0x00000000), material.Color(0xFF000000)],
          ).createShader(rect));
    final p = material.Offset(s * size.width, (1 - v) * size.height);
    canvas.drawCircle(
        p,
        8,
        material.Paint()
          ..style = material.PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring);
  }

  @override
  bool shouldRepaint(_SvPainter old) =>
      old.hue != hue || old.s != s || old.v != v || old.ring != ring;
}

class _Checkers extends material.CustomPainter {
  _Checkers(this.color);

  final material.Color color;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final paint = material.Paint()..color = color.withValues(alpha: 0.5);
    const cell = 7.0;
    for (var y = 0.0, row = 0; y < size.height; y += cell, row++) {
      for (var x = row.isEven ? 0.0 : cell; x < size.width; x += cell * 2) {
        canvas.drawRect(material.Rect.fromLTWH(x, y, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Checkers old) => old.color != color;
}
