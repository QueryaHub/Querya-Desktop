import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('QueryaModalDialog', () {
    testWidgets('renders title, description, content, and actions', (tester) async {
      var actionClicked = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaModalDialog(
            title: const Text('Dialog Title'),
            description: const Text('Dialog Subtitle'),
            icon: const material.Icon(material.Icons.info_outline),
            content: const Text('Dialog Content Body'),
            actions: [
              OutlineButton(
                onPressed: () => actionClicked = true,
                child: const Text('Action Button'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Dialog Title'), findsOneWidget);
      expect(find.text('Dialog Subtitle'), findsOneWidget);
      expect(find.text('Dialog Content Body'), findsOneWidget);
      expect(find.text('Action Button'), findsOneWidget);

      await tester.tap(find.text('Action Button'));
      expect(actionClicked, isTrue);
    });

    testWidgets('renders close button when showCloseButton is true', (tester) async {
      var closed = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaModalDialog(
            title: const Text('Title'),
            showCloseButton: true,
            onClose: () => closed = true,
          ),
        ),
      );

      final closeButton = find.byIcon(material.Icons.close_rounded);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      expect(closed, isTrue);
    });
  });

  group('QueryaConfirmDialog', () {
    testWidgets('renders confirmation UI with standard buttons', (tester) async {
      var confirmed = false;
      var cancelled = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: QueryaConfirmDialog(
            title: 'Delete Item?',
            message: 'Are you sure you want to proceed?',
            confirmLabel: 'Proceed',
            cancelLabel: 'Abort',
            onConfirm: () => confirmed = true,
            onCancel: () => cancelled = true,
          ),
        ),
      );

      expect(find.text('Delete Item?'), findsOneWidget);
      expect(find.text('Are you sure you want to proceed?'), findsOneWidget);
      expect(find.text('Proceed'), findsOneWidget);
      expect(find.text('Abort'), findsOneWidget);

      await tester.tap(find.text('Proceed'));
      expect(confirmed, isTrue);

      await tester.tap(find.text('Abort'));
      expect(cancelled, isTrue);
    });

    testWidgets('renders destructive confirm button when isDestructive is true',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const QueryaConfirmDialog(
            title: 'Drop Table?',
            message: 'This will destroy all data.',
            isDestructive: true,
            confirmLabel: 'Drop',
          ),
        ),
      );

      expect(find.byType(DestructiveButton), findsOneWidget);
      expect(find.text('Drop'), findsOneWidget);
    });
  });
}
