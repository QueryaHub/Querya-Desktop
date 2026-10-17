import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/core/ui/querya_tooltip.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _shell(material.Widget child) =>
    queryaThemeTestShell(child: material.Center(child: child));

void main() {
  group('QueryaButton activation', () {
    testWidgets('a tap fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _shell(QueryaButton.primary(label: 'Save', onPressed: () => taps++)),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('a disabled button does not fire', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _shell(const QueryaButton.secondary(label: 'Save')),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('a disabled primary is a grey chip, not a faded accent',
        (tester) async {
      await tester.pumpWidget(
        _shell(const QueryaButton.primary(label: 'Save')),
      );
      expect(
        find.descendant(
          of: find.byType(QueryaButton),
          matching: find.byType(material.Opacity),
        ),
        findsNothing,
      );

      // Other disabled variants still fade.
      await tester.pumpWidget(
        _shell(const QueryaButton.secondary(label: 'Save')),
      );
      expect(
        find.descendant(
          of: find.byType(QueryaButton),
          matching: find.byType(material.Opacity),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a loading button does not fire', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _shell(
          QueryaButton.primary(
            label: 'Save',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(QueryaButton));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('Enter and Space activate a focused button', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _shell(
          QueryaButton.secondary(
            label: 'Go',
            autofocus: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });
  });

  group('QueryaButton layout', () {
    for (final size in QueryaControlSize.values) {
      testWidgets('${size.name} is ${size.height} px tall', (tester) async {
        await tester.pumpWidget(
          _shell(
            QueryaButton.secondary(
              label: 'Explain',
              icon: material.Icons.account_tree_outlined,
              size: size,
              onPressed: () {},
            ),
          ),
        );

        expect(tester.getSize(find.byType(QueryaButton)).height, size.height);
      });
    }

    testWidgets('an icon-only button is square', (tester) async {
      await tester.pumpWidget(
        _shell(
          QueryaButton.icon(
            icon: material.Icons.refresh,
            tooltip: 'Refresh',
            size: QueryaControlSize.md,
            onPressed: () {},
          ),
        ),
      );

      final size = tester.getSize(find.byType(QueryaButton));
      expect(size.width, size.height);
      expect(size.height, QueryaControlSize.md.height);
    });

    testWidgets('compact hides the label and keeps it as the tooltip',
        (tester) async {
      await tester.pumpWidget(
        _shell(
          QueryaButton.secondary(
            label: 'Refresh',
            icon: material.Icons.refresh,
            compact: true,
            onPressed: () {},
          ),
        ),
      );

      expect(find.text('Refresh'), findsNothing);
      final tooltip = tester.widget<material.Tooltip>(
        find.byType(material.Tooltip),
      );
      expect(tooltip.message, 'Refresh');
    });

    testWidgets('loading keeps the width of the button', (tester) async {
      Future<double> width({required bool loading}) async {
        await tester.pumpWidget(
          _shell(
            QueryaButton.primary(
              label: 'Create connection',
              loading: loading,
              onPressed: () {},
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(QueryaButton)).width;
      }

      final idle = await width(loading: false);
      final busy = await width(loading: true);

      expect(busy, idle);
    });

    testWidgets('a long label ellipsizes on one line without overflow',
        (tester) async {
      await tester.pumpWidget(
        _shell(
          material.SizedBox(
            width: 90,
            child: QueryaButton.secondary(
              label: 'A label that is much too long for this button',
              icon: material.Icons.add,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<material.Text>(
        find.text('A label that is much too long for this button'),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, material.TextOverflow.ellipsis);
    });
  });

  group('QueryaButton tooltip and semantics', () {
    testWidgets('the tooltip waits kQueryaTooltipWait', (tester) async {
      await tester.pumpWidget(
        _shell(
          QueryaButton.ghost(
            label: 'Cancel',
            tooltip: 'Close without saving',
            onPressed: () {},
          ),
        ),
      );

      final tooltip = tester.widget<material.Tooltip>(
        find.byType(material.Tooltip),
      );
      expect(tooltip.waitDuration, kQueryaTooltipWait);
      expect(tooltip.message, 'Close without saving');
    });

    testWidgets('exposes button, enabled and selected state', (tester) async {
      await tester.pumpWidget(
        _shell(
          QueryaButton.ghost(
            label: 'Wrap',
            isActive: true,
            onPressed: () {},
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.enabled == true &&
              w.properties.selected == true &&
              w.properties.label == 'Wrap',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a disabled button is exposed as disabled', (tester) async {
      await tester.pumpWidget(
        _shell(const QueryaButton.primary(label: 'Save')),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is material.Semantics &&
              w.properties.button == true &&
              w.properties.enabled == false,
        ),
        findsOneWidget,
      );
    });
  });

  test('the button file imports no shadcn_flutter', () {
    final source =
        File('lib/shared/widgets/querya_button.dart').readAsStringSync();

    // Only an import counts: the doc comment names the package.
    expect(
      RegExp(r'''^(import|export)\s+['"]package:shadcn_flutter/''',
              multiLine: true)
          .hasMatch(source),
      isFalse,
    );
  });

  group('QueryaButton truncated label (#1689)', () {
    const long = 'Export the current result set as CSV';
    Finder tooltipWith(String message) => find.byWidgetPredicate(
          (w) => w is material.Tooltip && w.message == message,
        );

    testWidgets('a label cut short shows its full text as a tooltip',
        (tester) async {
      await tester.pumpWidget(_shell(material.SizedBox(
        width: 90,
        child: QueryaButton.secondary(label: long, onPressed: () {}),
      )));

      expect(tooltipWith(long), findsOneWidget);
    });

    testWidgets('a label that fits gets no tooltip', (tester) async {
      await tester.pumpWidget(_shell(material.SizedBox(
        width: 240,
        child: QueryaButton.secondary(label: 'Save', onPressed: () {}),
      )));

      expect(find.byType(material.Tooltip), findsNothing);
    });

    testWidgets('an explicit tooltip wins over the cut label', (tester) async {
      await tester.pumpWidget(_shell(material.SizedBox(
        width: 90,
        child: QueryaButton.secondary(
          label: long,
          tooltip: 'Export as CSV',
          onPressed: () {},
        ),
      )));

      expect(tooltipWith(long), findsNothing);
      expect(tooltipWith('Export as CSV'), findsOneWidget);
    });
  });
}
