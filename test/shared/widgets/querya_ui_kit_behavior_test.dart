import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

/// The sized box that wraps the progress indicator.
Finder _spinnerBox() => find
    .ancestor(
      of: find.byType(material.CircularProgressIndicator),
      matching: find.byType(material.SizedBox),
    )
    .first;

void main() {
  group('QueryaSearchField', () {
    testWidgets('Escape clears the text and reports an empty query',
        (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaSearchField(
              autofocus: true,
              debounceDuration: Duration.zero,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(material.TextField), 'orders');
      await tester.pump();
      expect(changes, ['orders']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(
        tester.widget<material.TextField>(find.byType(material.TextField))
            .controller!.text,
        isEmpty,
      );
      expect(changes.last, '');
    });

    testWidgets('only the last keystroke inside the debounce window is reported',
        (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaSearchField(
              debounceDuration: const Duration(milliseconds: 300),
              onChanged: changes.add,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(material.TextField), 'o');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(material.TextField), 'or');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(material.TextField), 'ord');
      expect(changes, isEmpty);

      await tester.pump(const Duration(milliseconds: 350));

      expect(changes, ['ord']);
    });

    testWidgets('the shortcut hint is replaced by the clear button once typing',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: QueryaSearchField(shortcutHint: 'Ctrl+K'),
          ),
        ),
      );
      expect(find.text('Ctrl+K'), findsOneWidget);
      expect(find.byIcon(material.Icons.close_rounded), findsNothing);

      await tester.enterText(find.byType(material.TextField), 'x');
      await tester.pump();

      expect(find.text('Ctrl+K'), findsNothing);
      expect(find.byIcon(material.Icons.close_rounded), findsOneWidget);
    });

    testWidgets('an external controller is not disposed with the field',
        (tester) async {
      final controller = material.TextEditingController(text: 'kept');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaSearchField(controller: controller),
          ),
        ),
      );
      expect(find.text('kept'), findsOneWidget);

      await tester.pumpWidget(
        queryaThemeTestShell(child: const material.SizedBox.shrink()),
      );

      expect(controller.text, 'kept');
      controller.text = 'still usable';
    });
  });

  group('QueryaIconButton', () {
    testWidgets('without onPressed the button is disabled', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: QueryaIconButton(
              icon: material.Icon(material.Icons.add_rounded),
            ),
          ),
        ),
      );

      final ink = tester.widget<material.InkWell>(find.byType(material.InkWell));
      expect(ink.onTap, isNull);
    });

    testWidgets('a tooltip message is attached when given', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: QueryaIconButton(
              icon: const material.Icon(material.Icons.add_rounded),
              tooltip: 'Add row',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('Add row'), findsOneWidget);
    });
  });

  group('QueryaSpinner', () {
    Future<material.CircularProgressIndicator> pump(
      WidgetTester tester,
      QueryaSpinner spinner,
    ) async {
      await tester.pumpWidget(
        queryaThemeTestShell(child: material.Scaffold(body: spinner)),
      );
      return tester.widget<material.CircularProgressIndicator>(
        find.byType(material.CircularProgressIndicator),
      );
    }

    testWidgets('stroke width grows with the preset', (tester) async {
      expect((await pump(tester, const QueryaSpinner(size: QueryaSpinnerSize.sm)))
              .strokeWidth,
          2.0);
      expect((await pump(tester, const QueryaSpinner(size: QueryaSpinnerSize.md)))
              .strokeWidth,
          2.5);
      expect((await pump(tester, const QueryaSpinner(size: QueryaSpinnerSize.lg)))
              .strokeWidth,
          3.0);
    });

    testWidgets('medium is the default size', (tester) async {
      await pump(tester, const QueryaSpinner());

      expect(tester.getSize(_spinnerBox()), const material.Size(20, 20));
    });

    testWidgets('custom dimension, stroke and color override the preset',
        (tester) async {
      final indicator = await pump(
        tester,
        const QueryaSpinner(
          size: QueryaSpinnerSize.sm,
          customDimension: 40,
          strokeWidth: 5,
          color: material.Color(0xFF123456),
        ),
      );

      expect(indicator.strokeWidth, 5);
      expect(indicator.valueColor!.value, const material.Color(0xFF123456));
      expect(tester.getSize(_spinnerBox()), const material.Size(40, 40));
    });
  });

  group('QueryaConfirmDialog.show', () {
    Future<void> open(
      WidgetTester tester,
      void Function(bool?) onResult, {
      bool isDestructive = false,
    }) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.Scaffold(
              body: material.Center(
                child: material.TextButton(
                  onPressed: () async => onResult(
                    await QueryaConfirmDialog.show(
                      context: context,
                      title: 'Delete row?',
                      message: 'This cannot be undone.',
                      confirmLabel: 'Delete',
                      isDestructive: isDestructive,
                    ),
                  ),
                  child: const material.Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirming resolves to true', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Delete row?'), findsNothing);
    });

    testWidgets('cancelling resolves to false', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('a destructive confirmation uses the destructive button',
        (tester) async {
      await open(tester, (_) {}, isDestructive: true);

      expect(find.byType(DestructiveButton), findsOneWidget);
    });
  });
}
