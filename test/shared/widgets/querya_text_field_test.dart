import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';
import 'package:querya_desktop/shared/widgets/querya_button.dart';
import 'package:querya_desktop/shared/widgets/querya_text_field.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  Future<void> pump(WidgetTester t, material.Widget field,
      {QueryaControlSize? scope}) async {
    await t.pumpWidget(queryaThemeTestShell(
      child: material.Center(
        child: material.SizedBox(
          width: 320,
          child: scope == null
              ? field
              : QueryaControlScope(size: scope, child: field),
        ),
      ),
    ));
  }

  double heightOf(WidgetTester t) => t.getSize(find.byType(QueryaTextField)).height;

  group('size', () {
    testWidgets('a single line has the control height, md by default',
        (t) async {
      await pump(t, const QueryaTextField());
      expect(heightOf(t), QueryaControlSize.md.height);
    });

    testWidgets('it follows the control scope and an explicit size',
        (t) async {
      await pump(t, const QueryaTextField(), scope: QueryaControlSize.lg);
      expect(heightOf(t), QueryaControlSize.lg.height);

      await pump(t, const QueryaTextField(size: QueryaControlSize.sm));
      expect(heightOf(t), QueryaControlSize.sm.height);
    });

    testWidgets('a field and a button of one size in a row are one height',
        (t) async {
      await t.pumpWidget(queryaThemeTestShell(
        child: const material.Center(
          child: QueryaControlScope(
            size: QueryaControlSize.md,
            child: material.Row(children: [
              material.SizedBox(width: 200, child: QueryaTextField()),
              QueryaButton.secondary(label: 'Browse…'),
            ]),
          ),
        ),
      ));
      expect(t.getSize(find.byType(QueryaTextField)).height,
          t.getSize(find.byType(QueryaButton)).height);
    });

    testWidgets('a multi-line field grows past one line', (t) async {
      await pump(t, const QueryaTextField(minLines: 4, maxLines: 4));
      expect(heightOf(t), greaterThan(QueryaControlSize.md.height * 2));
    });
  });

  group('text', () {
    testWidgets('typing reaches the controller and onChanged', (t) async {
      final c = material.TextEditingController();
      addTearDown(c.dispose);
      final seen = <String>[];
      await pump(t, QueryaTextField(controller: c, onChanged: seen.add));
      await t.enterText(find.byType(QueryaTextField), 'abc');
      expect(c.text, 'abc');
      expect(seen, ['abc']);
    });

    testWidgets('the placeholder shows while the field is empty',
        (t) async {
      final c = material.TextEditingController();
      addTearDown(c.dispose);
      await pump(t, QueryaTextField(controller: c, placeholder: 'host'));
      expect(find.text('host'), findsOneWidget);
      // Typing hides the hint (the decorator fades it out).
      await t.enterText(find.byType(QueryaTextField), 'x');
      await t.pumpAndSettle();
      final hint = t.widget<material.AnimatedOpacity>(find.ancestor(
          of: find.text('host'), matching: find.byType(material.AnimatedOpacity)));
      expect(hint.opacity, 0);
    });

    testWidgets('submit calls onSubmitted', (t) async {
      String? submitted;
      await pump(t, QueryaTextField(onSubmitted: (v) => submitted = v));
      await t.enterText(find.byType(QueryaTextField), 'go');
      await t.testTextInput.receiveAction(material.TextInputAction.done);
      expect(submitted, 'go');
    });

    testWidgets('disabled and read-only fields refuse typing', (t) async {
      final c = material.TextEditingController(text: 'fixed');
      addTearDown(c.dispose);
      await pump(t, QueryaTextField(controller: c, readOnly: true));
      final editable = t.widget<material.EditableText>(
          find.byType(material.EditableText));
      expect(editable.readOnly, isTrue);

      await pump(t, QueryaTextField(controller: c, enabled: false));
      expect(
          t.widget<material.TextField>(find.byType(material.TextField)).enabled,
          isFalse);
    });
  });

  group('obscure', () {
    testWidgets('the text is hidden; the button shows and hides it',
        (t) async {
      final c = material.TextEditingController(text: 'secret');
      addTearDown(c.dispose);
      await pump(t, QueryaTextField(controller: c, obscureText: true));
      bool obscured() =>
          t.widget<material.EditableText>(find.byType(material.EditableText))
              .obscureText;
      expect(obscured(), isTrue);

      await t.tap(find.byType(QueryaButton));
      await t.pump();
      expect(obscured(), isFalse);
      await t.tap(find.byType(QueryaButton));
      await t.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('a trailing widget of the caller replaces the button',
        (t) async {
      await pump(
          t,
          const QueryaTextField(
              obscureText: true, trailing: material.Icon(material.Icons.key)));
      expect(find.byIcon(material.Icons.key), findsOneWidget);
      expect(find.byType(QueryaButton), findsNothing);
    });
  });

  group('slots and states', () {
    testWidgets('leading and trailing are shown', (t) async {
      await pump(
          t,
          const QueryaTextField(
            leading: material.Icon(material.Icons.search_rounded),
            trailing: material.Icon(material.Icons.close_rounded),
          ));
      expect(find.byIcon(material.Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(material.Icons.close_rounded), findsOneWidget);
    });

    testWidgets('an error text is shown under the field', (t) async {
      await pump(t, const QueryaTextField(errorText: 'Port must be a number'));
      expect(find.text('Port must be a number'), findsOneWidget);
    });

    testWidgets('the border follows the focus', (t) async {
      final node = material.FocusNode();
      addTearDown(node.dispose);
      await pump(t, QueryaTextField(focusNode: node));

      Object border() => (t
              .widget<material.Container>(find
                  .descendant(
                      of: find.byType(QueryaTextField),
                      matching: find.byType(material.Container))
                  .first)
              .decoration! as material.BoxDecoration)
          .border!;
      final idle = border();
      node.requestFocus();
      await t.pump();
      expect(border(), isNot(idle));
    });

    testWidgets('unframed, it draws no box of its own', (t) async {
      await pump(t, const QueryaTextField(framed: false));
      expect(
          find.descendant(
              of: find.byType(QueryaTextField),
              matching: find.byType(material.DecoratedBox)),
          findsNothing);
    });
  });
}
