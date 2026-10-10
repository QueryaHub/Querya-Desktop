/// The scroll offset that brings item [index] of a fixed-extent list into the
/// viewport, or null when it is already fully visible (#1369).
///
/// [offset] is the current scroll position and [viewportExtent] the visible
/// height. [leadingPadding] / [trailingPadding] are the list's own padding, so
/// the first and last rows can be revealed with their margin.
double? revealOffsetForItem({
  required int index,
  required double itemExtent,
  required double offset,
  required double viewportExtent,
  double leadingPadding = 0,
  double trailingPadding = 0,
}) {
  final top = leadingPadding + index * itemExtent;
  final bottom = top + itemExtent;
  if (top < offset) {
    return (top - leadingPadding).clamp(0.0, double.infinity);
  }
  if (bottom > offset + viewportExtent) {
    return bottom + trailingPadding - viewportExtent;
  }
  return null;
}
