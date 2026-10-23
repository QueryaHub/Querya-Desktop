import 'dart:math' as math;

/// How the category labels under a bar / line chart are laid out.
enum XLabelLayout {
  /// One line each, whole text.
  horizontal,

  /// Up to two lines each, whole words.
  wrapped,

  /// One line each, turned 45°, cut at [XLabelPlan.labelMaxWidth].
  rotated,
}

/// The layout [ChartAxisLabels.planX] picked.
class XLabelPlan {
  const XLabelPlan({
    required this.layout,
    required this.step,
    required this.slot,
    required this.labelMaxWidth,
    required this.reserved,
  });

  final XLabelLayout layout;

  /// Every [step]th label is drawn; 1 draws all of them.
  final int step;

  /// Width each drawn label may take: the distance between two drawn labels.
  final double slot;

  /// Widest a rotated label gets before it is cut; the slot otherwise.
  final double labelMaxWidth;

  /// Height the axis reserves under the plot for the labels.
  final double reserved;
}

/// Layout rules for chart axis labels, shared by the screen and the SVG export
/// so the two read the same. Pure: text widths come from a callback.
abstract final class ChartAxisLabels {
  /// A rotated label is cut at this width.
  static const double maxRotatedWidth = 140;

  /// Space kept between two neighbouring labels.
  static const double gap = 8;

  /// Picks how the [labels] fit under a plot [plotWidth] wide, in this order:
  /// every label on one line; every label on two lines; every label turned 45°;
  /// every nth label turned 45°. Dropping labels is the last resort, since the
  /// bar or point is still there but nothing says what it is.
  static XLabelPlan planX({
    required List<String> labels,
    required double plotWidth,
    required double Function(String text) measure,
    required double lineHeight,
  }) {
    final count = labels.length;
    if (count == 0) {
      return XLabelPlan(
        layout: XLabelLayout.horizontal,
        step: 1,
        slot: plotWidth,
        labelMaxWidth: plotWidth,
        reserved: lineHeight + 10,
      );
    }
    final slot = plotWidth / count;
    final room = slot - gap;
    final widths = [for (final l in labels) measure(l)];
    final widest = widths.reduce(math.max);

    if (widest <= room) {
      return XLabelPlan(
        layout: XLabelLayout.horizontal,
        step: 1,
        slot: slot,
        labelMaxWidth: slot,
        reserved: lineHeight + 10,
      );
    }

    if (room > 0 && _wraps(labels, widths, room, measure)) {
      return XLabelPlan(
        layout: XLabelLayout.wrapped,
        step: 1,
        slot: slot,
        labelMaxWidth: slot,
        reserved: lineHeight * 2 + 10,
      );
    }

    // A turned label needs about a line and a third of height between two.
    final step = math.max(1, (lineHeight * 1.3 / slot).ceil());
    final cap = math.min(widest, maxRotatedWidth);
    return XLabelPlan(
      layout: XLabelLayout.rotated,
      step: step,
      slot: slot * step,
      labelMaxWidth: cap,
      reserved: (cap + lineHeight) * math.sqrt1_2 + 10,
    );
  }

  /// Whether every label breaks into at most two lines of [room] width: its
  /// longest word fits, and the whole text fits twice over (with some slack,
  /// since a break wastes the end of the first line).
  static bool _wraps(
    List<String> labels,
    List<double> widths,
    double room,
    double Function(String) measure,
  ) {
    for (var i = 0; i < labels.length; i++) {
      if (widths[i] <= room) continue;
      final words = labels[i].split(RegExp(r'\s+'));
      if (words.length < 2) return false;
      if (words.map(measure).reduce(math.max) > room) return false;
      if (widths[i] > room * 2 * 0.85) return false;
    }
    return true;
  }

  /// [text] cut to at most [maxChars] characters, with an ellipsis.
  static String ellipsize(String text, int maxChars) {
    if (maxChars < 2 || text.length <= maxChars) return text;
    return '${text.substring(0, maxChars - 1).trimRight()}…';
  }
}
