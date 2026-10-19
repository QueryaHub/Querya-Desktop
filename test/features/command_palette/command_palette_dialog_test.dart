import 'package:flutter/widgets.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_text_field.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/features/command_palette/command_palette_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  final registry = QueryaCommandRegistry.instance;

  setUp(registry.resetForTest);
  tearDown(registry.resetForTest);

  Future<void> pumpPalette(WidgetTester tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: Builder(
            builder: (context) {
              return Center(
                child: material.ElevatedButton(
                  onPressed: () => showCommandPalette(context),
                  child: const Text('Open palette'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open palette'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('opens core commands and filters the list', (tester) async {
    registry.ensureCoreDefaults();
    await pumpPalette(tester);

    expect(find.text('Type a command…'), findsOneWidget);
    expect(find.text('Toggle Dark/Light Theme'), findsOneWidget);

    await tester.enterText(find.byType(QueryaTextField), 'dark');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('querya.theme.toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('querya.connection.new')), findsNothing);
  });

  testWidgets('hovering over an item updates selection without redundant search', (tester) async {
    registry.register(
      QueryaCommand(
        id: 'test.cmd.1',
        title: 'Command 1',
        category: 'Test',
        execute: (_) {},
      ),
    );
    registry.register(
      QueryaCommand(
        id: 'test.cmd.2',
        title: 'Command 2',
        category: 'Test',
        execute: (_) {},
      ),
    );
    await pumpPalette(tester);

    final firstItem = find.byKey(const ValueKey('test.cmd.1'));
    final secondItem = find.byKey(const ValueKey('test.cmd.2'));

    expect(firstItem, findsOneWidget);
    expect(secondItem, findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(firstItem));
    await tester.pump();

    // Hover over second item
    await gesture.moveTo(tester.getCenter(secondItem));
    await tester.pump();

    final inkWellFinder = find.byKey(const ValueKey('test.cmd.2'));
    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(of: inkWellFinder, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoratedBox.decoration as BoxDecoration;
    expect(boxDecoration.color, isNot(equals(material.Colors.transparent)));

    await gesture.removePointer();
  });

  testWidgets('Escape closes the palette', (tester) async {
    registry.ensureCoreDefaults();
    await pumpPalette(tester);
    expect(find.text('Type a command…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Type a command…'), findsNothing);
  });

  testWidgets('selecting a command executes and closes', (tester) async {
    var ran = 0;
    registry.register(
      QueryaCommand(
        id: 'test.palette.run',
        title: 'Palette Test Command',
        category: 'Test',
        execute: (_) => ran++,
      ),
    );

    await pumpPalette(tester);
    await tester.tap(find.text('Palette Test Command'));
    await tester.pumpAndSettle();

    expect(ran, 1);
    expect(find.text('Palette Test Command'), findsNothing);
  });

  testWidgets('Motion Off uses zero dialog enter duration', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.off,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(
      QueryaMotion.effectiveDuration(ctx, QueryaMotion.standard),
      Duration.zero,
    );
  });
}
