import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('Menubar dropdown opens fast and toggles on repeated tap',
      (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        menuHandler: const PopoverOverlayHandler(
          defaultShowDuration: Duration(milliseconds: 60),
          defaultDismissDuration: Duration(milliseconds: 50),
          showCurve: Curves.easeOutCubic,
          dismissCurve: Curves.easeIn,
        ),
        home: material.Scaffold(
          body: material.Column(
            children: [
              Menubar(
                border: false,
                children: [
                  MenuButton(
                    subMenu: [
                      MenuButton(
                        onPressed: (_) {},
                        child: const Text('New File'),
                      ),
                      MenuButton(
                        onPressed: (_) {},
                        child: const Text('Save File'),
                      ),
                    ],
                    child: const Text('File'),
                  ),
                  MenuButton(
                    subMenu: [
                      MenuButton(
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
    // Advance by 60ms (the fast open duration)
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('New File'), findsOneWidget);
    expect(find.text('Save File'), findsOneWidget);

    // Tap 'File' again to toggle close
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('New File'), findsNothing);

    // Open 'File' again
    await tester.tap(find.text('File'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('New File'), findsOneWidget);

    // Tap 'Edit' while 'File' is open -> closes 'File' immediately and opens 'Edit'
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('New File'), findsNothing);
    expect(find.text('Undo Action'), findsOneWidget);

    // Tap outside -> closes 'Edit' menu
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(find.text('Undo Action'), findsNothing);
  });
}
