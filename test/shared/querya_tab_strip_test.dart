import 'dart:ui' show Tristate;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  material.Widget stripShell({
    required material.Widget child,
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) {
    return queryaThemeTestShell(
      child: QueryaMotionScope(
        level: level,
        child: child,
      ),
    );
  }

  material.Positioned indicatorOf(WidgetTester tester) {
    return tester.widget<material.Positioned>(
      find.byKey(const material.ValueKey('querya_tab_indicator')),
    );
  }

  Future<void> pumpSettledStrip(
    WidgetTester tester, {
    required int selected,
    required material.ValueChanged<int> onSelected,
    QueryaMotionLevel level = QueryaMotionLevel.full,
    List<String> labels = const ['Server', 'SQL', 'History'],
  }) async {
    await tester.pumpWidget(
      stripShell(
        level: level,
        child: material.Center(
          child: QueryaTabStrip(
            labels: labels,
            selectedIndex: selected,
            onSelected: onSelected,
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame indicator sync
    await tester.pumpAndSettle();
  }

  testWidgets('exposes button and selected semantics', (tester) async {
    var selected = 0;
    await pumpSettledStrip(
      tester,
      selected: selected,
      onSelected: (index) => selected = index,
      labels: const ['Server', 'SQL'],
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
      stripShell(
        child: material.StatefulBuilder(
          builder: (context, setState) => QueryaTabStrip(
            labels: const ['Server', 'SQL', 'History'],
            selectedIndex: selected,
            onSelected: (index) => setState(() => selected = index),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

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

  testWidgets('renders sliding indicator under selected tab', (tester) async {
    await pumpSettledStrip(
      tester,
      selected: 1,
      onSelected: (_) {},
    );

    expect(find.byKey(const material.ValueKey('querya_tab_indicator')),
        findsOneWidget);
    final indicator = indicatorOf(tester);
    final sql = tester.getRect(find.byKey(const material.ValueKey('querya_tab_SQL')));
    final strip = tester.getRect(find.byType(QueryaTabStrip));

    expect(indicator.left, closeTo(sql.left - strip.left, 1.0));
    expect(indicator.width, closeTo(sql.width, 1.0));
  });

  testWidgets('indicator slides toward newly selected tab (full motion)',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      stripShell(
        child: material.StatefulBuilder(
          builder: (context, setState) => material.Center(
            child: QueryaTabStrip(
              labels: const ['Server', 'SQL', 'History'],
              selectedIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final startLeft = indicatorOf(tester).left!;

    await tester.tap(find.bySemanticsLabel('History'));
    await tester.pump(); // selection + schedule
    await tester.pump(); // post-frame sync starts spring
    await tester.pump(const Duration(milliseconds: 40));

    final midLeft = indicatorOf(tester).left!;
    expect(midLeft, greaterThan(startLeft));

    await tester.pumpAndSettle();
    final history =
        tester.getRect(find.byKey(const material.ValueKey('querya_tab_History')));
    final strip = tester.getRect(find.byType(QueryaTabStrip));
    expect(
      indicatorOf(tester).left,
      closeTo(history.left - strip.left, 1.0),
    );
  });

  testWidgets('motion off snaps indicator without mid-flight offset',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      stripShell(
        level: QueryaMotionLevel.off,
        child: material.StatefulBuilder(
          builder: (context, setState) => material.Center(
            child: QueryaTabStrip(
              labels: const ['Server', 'SQL', 'History'],
              selectedIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('History'));
    await tester.pump();
    await tester.pump(); // post-frame jump

    final history =
        tester.getRect(find.byKey(const material.ValueKey('querya_tab_History')));
    final strip = tester.getRect(find.byType(QueryaTabStrip));
    expect(
      indicatorOf(tester).left,
      closeTo(history.left - strip.left, 1.0),
    );
  });

  testWidgets('redirect mid-slide settles on final selection', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      stripShell(
        child: material.StatefulBuilder(
          builder: (context, setState) => material.Center(
            child: QueryaTabStrip(
              labels: const ['Server', 'SQL', 'History'],
              selectedIndex: selected,
              onSelected: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('History'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    await tester.tap(find.bySemanticsLabel('SQL'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final sql = tester.getRect(find.byKey(const material.ValueKey('querya_tab_SQL')));
    final strip = tester.getRect(find.byType(QueryaTabStrip));
    expect(
      indicatorOf(tester).left,
      closeTo(sql.left - strip.left, 1.0),
    );
    expect(selected, 1);
  });

  testWidgets('indicator uses RepaintBoundary and stays under Stack',
      (tester) async {
    await pumpSettledStrip(
      tester,
      selected: 0,
      onSelected: (_) {},
    );

    expect(
      find.descendant(
        of: find.byKey(const material.ValueKey('querya_tab_indicator')),
        matching: find.byType(material.RepaintBoundary),
      ),
      findsOneWidget,
    );
    final stack = tester.widget<material.Stack>(find.byType(material.Stack));
    expect(stack.children.length, 2);
  });

  testWidgets('OS disableAnimations snaps indicator', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      material.MediaQuery(
        data: const material.MediaQueryData(disableAnimations: true),
        child: stripShell(
          child: material.StatefulBuilder(
            builder: (context, setState) => material.Center(
              child: QueryaTabStrip(
                labels: const ['Server', 'SQL'],
                selectedIndex: selected,
                onSelected: (index) => setState(() => selected = index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('SQL'));
    await tester.pump();
    await tester.pump();

    final sql = tester.getRect(find.byKey(const material.ValueKey('querya_tab_SQL')));
    final strip = tester.getRect(find.byType(QueryaTabStrip));
    expect(
      indicatorOf(tester).left,
      closeTo(sql.left - strip.left, 1.0),
    );
  });
}
