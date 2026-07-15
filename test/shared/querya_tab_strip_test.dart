import 'dart:ui' show Tristate;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('exposes button and selected semantics', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.StatefulBuilder(
          builder: (context, setState) => QueryaTabStrip(
            labels: const ['Server', 'SQL'],
            selectedIndex: selected,
            onSelected: (index) => setState(() => selected = index),
          ),
        ),
      ),
    );

    final server = tester.getSemantics(find.bySemanticsLabel('Server'));
    final sql = tester.getSemantics(find.bySemanticsLabel('SQL'));
    expect(server.flagsCollection.isButton, isTrue);
    expect(server.flagsCollection.isSelected, Tristate.isTrue);
    expect(sql.flagsCollection.isButton, isTrue);
    expect(sql.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('supports arrows, Home, End, and visible keyboard focus',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.StatefulBuilder(
          builder: (context, setState) => QueryaTabStrip(
            labels: const ['Server', 'SQL', 'History'],
            selectedIndex: selected,
            onSelected: (index) => setState(() => selected = index),
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Server'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(selected, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(selected, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(selected, 2);

    final focusedTab = tester.widget<material.AnimatedContainer>(
      find.byKey(const material.ValueKey('querya_tab_History')),
    );
    final decoration = focusedTab.decoration! as material.BoxDecoration;
    expect(
      (decoration.border! as material.Border).top.color,
      isNot(material.Colors.transparent),
    );
  });
}
