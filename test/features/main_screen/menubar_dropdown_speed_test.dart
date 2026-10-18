import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';
import 'package:querya_desktop/shared/widgets/querya_menu_bar.dart';

void main() {
  testWidgets('QueryaMenuBar dropdown opens and toggles on repeated tap',
      (tester) async {
    await tester.pumpWidget(
      material.MaterialApp(
        home: material.Scaffold(
          body: material.Column(
            children: [
              QueryaMenuBar(
                children: [
                  QueryaMenuItem(
                    subMenu: [
                      QueryaMenuItem(
                        onPressed: (_) {},
                        child: const Text('New File'),
                      ),
                      QueryaMenuItem(
                        onPressed: (_) {},
                        child: const Text('Save File'),
                      ),
                    ],
                    child: const Text('File'),
                  ),
                  QueryaMenuItem(
                    subMenu: [
                      QueryaMenuItem(
                        onPressed: (_) {},
                        child: const Text('Undo Action'),
                      ),
                    ],
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Initial state: menu items are not visible
    expect(find.text('New File'), findsNothing);
    expect(find.text('Undo Action'), findsNothing);

    // Tap 'File'
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('New File'), findsOneWidget);
    expect(find.text('Save File'), findsOneWidget);

    // Tap 'File' again to toggle close
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('New File'), findsNothing);

    // Open 'File' again
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('New File'), findsOneWidget);

    // Tap 'Edit' while 'File' is open -> closes 'File' and opens 'Edit'
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('New File'), findsNothing);
    expect(find.text('Undo Action'), findsOneWidget);

    // Tap outside -> closes 'Edit' menu
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(find.text('Undo Action'), findsNothing);
  });
}
