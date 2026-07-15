import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_semantic_palette.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('semantic palette derives roles from theme tokens', () {
    const action = Color(0xFF010101);
    const success = Color(0xFF020202);
    const destructive = Color(0xFF030303);
    const muted = Color(0xFF040404);
    const chart1 = Color(0xFF111111);
    const chart2 = Color(0xFF222222);
    const chart3 = Color(0xFF333333);
    const chart4 = Color(0xFF444444);
    const chart5 = Color(0xFF555555);

    const base = QueryaTheme.darkDefault;
    final theme = base.copyWith(
      workbench: base.workbench.copyWith(
        accent: action,
        success: success,
        destructive: destructive,
        mutedForeground: muted,
      ),
      colorScheme: base.colorScheme.copyWith(
        chart1: () => chart1,
        chart2: () => chart2,
        chart3: () => chart3,
        chart4: () => chart4,
        chart5: () => chart5,
      ),
    );

    final palette = QueryaSemanticPalette.fromTheme(theme);

    expect(palette.action, action);
    expect(palette.success, success);
    expect(palette.destructive, destructive);
    expect(palette.muted, muted);
    expect(
      [
        palette.type1,
        palette.type2,
        palette.type3,
        palette.type4,
        palette.type5,
      ],
      [chart1, chart2, chart3, chart4, chart5],
    );
  });
}
