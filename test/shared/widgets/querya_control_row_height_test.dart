import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';
import 'package:querya_desktop/shared/widgets/querya_icon_button.dart';
import 'package:querya_desktop/shared/widgets/querya_search_field.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _row({
  QueryaControlSize? size,
  double uiScale = 1,
  bool wrapInScope = false,
}) {
  final controls = material.Row(
    mainAxisSize: material.MainAxisSize.min,
    crossAxisAlignment: material.CrossAxisAlignment.start,
    children: [
      QueryaIconButton(
        key: const material.ValueKey('icon'),
        icon: const material.Icon(material.Icons.refresh),
        tooltip: 'Refresh',
        onPressed: () {},
        size: size,
      ),
      material.SizedBox(
        width: 160,
        child: QueryaDropdown<String>(
          key: const material.ValueKey('dropdown'),
          value: 'a',
          items: const [
            QueryaDropdownItem(value: 'a', label: 'Alpha'),
            QueryaDropdownItem(value: 'b', label: 'Beta'),
          ],
          onSelected: (_) {},
          size: size,
        ),
      ),
      material.SizedBox(
        width: 160,
        child: QueryaSearchField(
          key: const material.ValueKey('search'),
          size: size,
        ),
      ),
      QueryaTabStrip(
        key: const material.ValueKey('tabs'),
        labels: const ['One', 'Two'],
        selectedIndex: 0,
        onSelected: (_) {},
        size: size,
      ),
    ],
  );
  return queryaThemeTestShell(
    child: QueryaUiScaleScope(
      scale: uiScale,
      child: material.Center(
        child: wrapInScope && size != null
            ? QueryaControlScope(size: size, child: controls)
            : controls,
      ),
    ),
  );
}

void main() {
  const keys = ['icon', 'dropdown', 'search', 'tabs'];

  Future<List<double>> heights(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
    return [
      for (final k in keys)
        tester.getSize(find.byKey(material.ValueKey(k))).height,
    ];
  }

  group('one control size gives one row height (#1333)', () {
    for (final size in QueryaControlSize.values) {
      for (final scale in [1.0, 1.25]) {
        testWidgets('${size.name} at ui scale $scale', (tester) async {
          await tester.pumpWidget(_row(size: size, uiScale: scale));

          final expected = size.height * scale;
          expect(await heights(tester), everyElement(closeTo(expected, 0.01)));
        });
      }
    }

    testWidgets('a control scope sets the size for the whole row',
        (tester) async {
      await tester.pumpWidget(
        _row(size: QueryaControlSize.md, wrapInScope: true),
      );

      // The scope is the only source here: the controls get no size.
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Center(
            child: QueryaControlScope(
              size: QueryaControlSize.sm,
              child: material.Row(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  QueryaIconButton(
                    key: const material.ValueKey('icon'),
                    icon: const material.Icon(material.Icons.refresh),
                    onPressed: () {},
                  ),
                  material.SizedBox(
                    width: 160,
                    child: QueryaSearchField(
                      key: const material.ValueKey('search'),
                    ),
                  ),
                  QueryaTabStrip(
                    key: const material.ValueKey('tabs'),
                    labels: const ['One'],
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      for (final k in ['icon', 'search', 'tabs']) {
        expect(
          tester.getSize(find.byKey(material.ValueKey(k))).height,
          28,
          reason: k,
        );
      }
    });
  });
}
