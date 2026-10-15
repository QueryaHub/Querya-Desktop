import 'package:flutter/material.dart' as material;

/// Renders long text efficiently. If line count <= [threshold], uses a single
/// `SelectableText` inside `SingleChildScrollView` so multi-line selection across
/// the entire block works seamlessly.
/// If line count > [threshold], virtualizes lines using `ListView.builder` to
/// ensure 60 FPS scrolling and rendering without UI jank.
class VirtualSelectableTextView extends material.StatefulWidget {
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
  material.State<VirtualSelectableTextView> createState() =>
      _VirtualSelectableTextViewState();
}

class _VirtualSelectableTextViewState
    extends material.State<VirtualSelectableTextView> {
  /// `widget.text` split on `\n`. Computed when the text changes, not in
  /// `build`: resize, theme and focus rebuilds must not re-split a text of
  /// thousands of lines on every frame (#1532).
  late List<String> _lines = widget.text.split('\n');

  @override
  void didUpdateWidget(covariant VirtualSelectableTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _lines = widget.text.split('\n');
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final lines = _lines;
    if (lines.length <= widget.threshold) {
      return material.SingleChildScrollView(
        padding: widget.padding,
        child: material.SelectableText(
          widget.text,
          style: widget.style,
        ),
      );
    }

    return material.ListView.builder(
      padding: widget.padding,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return material.SelectableText(
          lines[index],
          style: widget.style,
        );
      },
    );
  }
}
