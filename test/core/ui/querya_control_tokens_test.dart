import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_icon_button.dart';

void main() {
  group('QueryaControlSize', () {
    test('the three sizes are 28 / 32 / 36 with one radius', () {
      expect(QueryaControlSize.sm.height, 28);
      expect(QueryaControlSize.md.height, 32);
      expect(QueryaControlSize.lg.height, 36);
      expect(QueryaControlSize.sm.radius, 6);
      expect(QueryaControlSize.lg.radius, 6);
    });

    test('font, icon and padding grow with the size', () {
      const sizes = QueryaControlSize.values;
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i].fontSize, greaterThan(sizes[i - 1].fontSize));
        expect(sizes[i].iconSize, greaterThan(sizes[i - 1].iconSize));
        expect(
          sizes[i].horizontalPadding,
          greaterThan(sizes[i - 1].horizontalPadding),
        );
      }
    });

    test('legacy density names map to sm and md', () {
      expect(QueryaIconButtonDensity.dense.controlSize, QueryaControlSize.sm);
      expect(QueryaIconButtonDensity.standard.controlSize, QueryaControlSize.md);
      expect(QueryaIconButtonDensity.dense.boxSize, 28);
      expect(QueryaIconButtonDensity.standard.boxSize, 32);
    });

    test('the dropdown tokens are built from the scale', () {
      expect(QueryaDropdownTokens.triggerHeight, QueryaControlSize.lg.height);
      expect(
        QueryaDropdownTokens.compactTriggerHeight,
        QueryaControlSize.sm.height,
      );
      expect(QueryaDropdownTokens.menuItemHeight, QueryaControlSize.md.height);
    });
  });

  group('QueryaControlScope', () {
    Widget probe(void Function(QueryaControlSize) onSize) => Builder(
          builder: (context) {
            onSize(QueryaControlSize.of(context));
            return const SizedBox.shrink();
          },
        );

    testWidgets('defaults to md without a scope', (tester) async {
      late QueryaControlSize seen;
      await tester.pumpWidget(probe((s) => seen = s));
      expect(seen, QueryaControlSize.md);
    });

    testWidgets('the nearest scope wins', (tester) async {
      late QueryaControlSize seen;
      await tester.pumpWidget(
        QueryaControlScope(
          size: QueryaControlSize.lg,
          child: QueryaControlScope(
            size: QueryaControlSize.sm,
            child: probe((s) => seen = s),
          ),
        ),
      );
      expect(seen, QueryaControlSize.sm);
    });

    testWidgets('scaled helpers follow the ui scale', (tester) async {
      late double height;
      await tester.pumpWidget(
        QueryaUiScaleScope(
          scale: 1.25,
          child: Builder(
            builder: (context) {
              height = QueryaControlSize.md.scaledHeight(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(height, 40);
    });
  });
}
