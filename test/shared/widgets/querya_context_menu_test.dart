import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_menu_bar.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _shell(material.Widget child) => queryaThemeTestShell(
      child: material.Scaffold(
        body: material.Center(child: child),
      ),
    );

Future<void> _secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('QueryaContextMenu', () {
    testWidgets('opens on secondary click and fires onPressed',
        (tester) async {
      var item1Pressed = false;
      var item2Pressed = false;

      await tester.pumpWidget(
        _shell(
          QueryaContextMenu(
            items: [
              QueryaMenuItem(
                onPressed: (_) => item1Pressed = true,
                child: const material.Text('Item 1'),
              ),
              QueryaMenuItem(
                onTap: () => item2Pressed = true,
                child: const material.Text('Item 2'),
              ),
              const QueryaMenuDivider(),
              QueryaMenuItem(
                enabled: false,
                onTap: () {},
                child: const material.Text('Disabled Item'),
              ),
            ],
            child: const material.Text('Target Box'),
          ),
        ),
      );

      expect(find.text('Item 1'), findsNothing);
      expect(find.text('Item 2'), findsNothing);

      await _secondaryClick(tester, find.text('Target Box'));
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Disabled Item'), findsOneWidget);

      await tester.tap(find.text('Item 1'));
      await tester.pumpAndSettle();

      expect(item1Pressed, isTrue);
      expect(item2Pressed, isFalse);
      expect(find.text('Item 1'), findsNothing);
    });

    testWidgets('evaluates itemsBuilder lazily only when opened',
        (tester) async {
      var builds = 0;

      await tester.pumpWidget(
        _shell(
          QueryaContextMenu(
            itemsBuilder: (context) {
              builds++;
              return [
                QueryaMenuItem(
                  onTap: () {},
                  child: const material.Text('Lazy Item'),
                ),
              ];
            },
            child: const material.Text('Lazy Target'),
          ),
        ),
      );

      expect(builds, 0);

      await _secondaryClick(tester, find.text('Lazy Target'));
      expect(builds, 1);
      expect(find.text('Lazy Item'), findsOneWidget);

      await tester.tap(find.text('Lazy Item'));
      await tester.pumpAndSettle();
      expect(find.text('Lazy Item'), findsNothing);
    });

    testWidgets('supports submenu expansion', (tester) async {
      var subItemPressed = false;

      await tester.pumpWidget(
        _shell(
          QueryaContextMenu(
            items: [
              QueryaMenuItem(
                subMenu: [
                  QueryaMenuItem(
                    onTap: () => subItemPressed = true,
                    child: const material.Text('Nested Item'),
                  ),
                ],
                child: const material.Text('Parent Menu'),
              ),
            ],
            child: const material.Text('Submenu Target'),
          ),
        ),
      );

      await _secondaryClick(tester, find.text('Submenu Target'));
      expect(find.text('Parent Menu'), findsOneWidget);
      expect(find.text('Nested Item'), findsNothing);

      await tester.tap(find.text('Parent Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Nested Item'), findsOneWidget);

      await tester.tap(find.text('Nested Item'));
      await tester.pumpAndSettle();
      expect(subItemPressed, isTrue);
      expect(find.text('Nested Item'), findsNothing);
    });

    testWidgets('opens via contextMenu key shortcut', (tester) async {
      final focusNode = material.FocusNode();

      await tester.pumpWidget(
        _shell(
          QueryaContextMenu(
            items: [
              QueryaMenuItem(
                onTap: () {},
                child: const material.Text('Shortcut Item'),
              ),
            ],
            child: material.Focus(
              focusNode: focusNode,
              autofocus: true,
              child: const material.Text('Shortcut Target'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Shortcut Item'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Shortcut Item'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Shortcut Item'), findsNothing);
    });
  });

  group('QueryaMenuBar', () {
    testWidgets('opens dropdown and toggles on repeated tap', (tester) async {
      var newFilePressed = false;

      await tester.pumpWidget(
        _shell(
          material.Column(
            children: [
              QueryaMenuBar(
                children: [
                  QueryaMenuItem(
                    subMenu: [
                      QueryaMenuItem(
                        onTap: () => newFilePressed = true,
                        child: const material.Text('New File'),
                      ),
                      QueryaMenuItem(
                        onTap: () {},
                        child: const material.Text('Save File'),
                      ),
                    ],
                    child: const material.Text('File'),
                  ),
                  QueryaMenuItem(
                    subMenu: [
                      QueryaMenuItem(
                        onTap: () {},
                        child: const material.Text('Undo Action'),
                      ),
                    ],
                    child: const material.Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(find.text('New File'), findsNothing);
      expect(find.text('Undo Action'), findsNothing);

      // Tap 'File' to open
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      expect(find.text('New File'), findsOneWidget);
      expect(find.text('Save File'), findsOneWidget);

      // Tap 'File' again to toggle close
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      expect(find.text('New File'), findsNothing);

      // Open again and select an item
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New File'));
      await tester.pumpAndSettle();

      expect(newFilePressed, isTrue);
      expect(find.text('New File'), findsNothing);
    });
  });
}
