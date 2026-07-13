import 'package:flutter/material.dart' as material;

/// Renders long text efficiently. If line count <= [threshold], uses a single
/// `SelectableText` inside `SingleChildScrollView` so multi-line selection across
/// the entire block works seamlessly.
/// If line count > [threshold], virtualizes lines using `ListView.builder` to
/// ensure 60 FPS scrolling and rendering without UI jank.
class VirtualSelectableTextView extends material.StatelessWidget {
  const VirtualSelectableTextView({
    super.key,
    required this.text,
    this.style,
    this.threshold = 200,
    this.padding = const material.EdgeInsets.all(16),
  });

  final String text;
  final material.TextStyle? style;
  final int threshold;
  final material.EdgeInsets padding;

  @override
  material.Widget build(material.BuildContext context) {
    final lines = text.split('\n');
    if (lines.length <= threshold) {
      return material.SingleChildScrollView(
        padding: padding,
        child: material.SelectableText(
          text,
          style: style,
        ),
      );
    }

    return material.ListView.builder(
      padding: padding,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return material.SelectableText(
          lines[index],
          style: style,
        );
      },
    );
  }
}
