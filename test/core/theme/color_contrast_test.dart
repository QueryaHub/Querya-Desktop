import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/color_contrast.dart';

void main() {
  test('legibleSecondaryLabel keeps readable candidate', () {
    const candidate = Color(0xFF94A3B8);
    const background = Color(0xFF0C0C0C);
    const fallback = Color(0xFFF8FAFC);
    expect(
      legibleSecondaryLabel(
        candidate: candidate,
        background: background,
        fallback: fallback,
      ),
      candidate,
    );
  });

  test('legibleSecondaryLabel softens low-contrast candidate', () {
    const candidate = Color(0xFF4A3F7A);
    const background = Color(0xFF14102A);
    const fallback = Color(0xFFE8F4FF);
    final out = legibleSecondaryLabel(
      candidate: candidate,
      background: background,
      fallback: fallback,
    );
    expect(out, fallback.withValues(alpha: 0.72));
    expect(contrastRatio(out, background), greaterThan(4.0));
  });
}
