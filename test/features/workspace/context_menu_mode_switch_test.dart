import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/querya_context_menu.dart';

material.Widget _testShell({required material.Widget child}) {
  return material.MaterialApp(
    theme: material.ThemeData.dark(),
    home: material.Scaffold(
      body: child,
    ),
  );
}

Future<void> _secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

class _DynamicContextMenuTestHost extends material.StatefulWidget {
  const _DynamicContextMenuTestHost({
    super.key,
    required this.initialItems,
    this.initialItemsBuilder,
  });

  final List<material.Widget>? initialItems;
  final List<material.Widget> Function(material.BuildContext)? initialItemsBuilder;

  @override
  material.State<_DynamicContextMenuTestHost> createState() =>
      _DynamicContextMenuTestHostState();
}

class _DynamicContextMenuTestHostState
    extends material.State<_DynamicContextMenuTestHost> {
  late List<material.Widget>? items = widget.initialItems;
  late List<material.Widget> Function(material.BuildContext)? itemsBuilder =
      widget.initialItemsBuilder;

  void update({
    List<material.Widget>? newItems,
    List<material.Widget> Function(material.BuildContext)? newItemsBuilder,
  }) {
    setState(() {
      items = newItems;
      itemsBuilder = newItemsBuilder;
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Center(
      child: QueryaContextMenu(
        items: items,
        itemsBuilder: itemsBuilder,
        child: const material.Text('Target Box'),
      ),
    );
  }
}

void main() {
  group('QueryaContextMenu mode switching (#1011)', () {
    testWidgets(
        'switches from itemsBuilder to items at runtime without throwing',
        (tester) async {
      final hostKey =
          material.GlobalKey<_DynamicContextMenuTestHostState>();

      await tester.pumpWidget(
        _testShell(
          child: _DynamicContextMenuTestHost(
            key: hostKey,
            initialItems: null,
            initialItemsBuilder: (context) => [
              const QueryaMenuItem(child: Text('Lazy Item 1')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to eager items without itemsBuilder
      hostKey.currentState!.update(
        newItems: [
          const QueryaMenuItem(child: Text('Eager Item 1')),
        ],
        newItemsBuilder: null,
      );
      await tester.pumpAndSettle();

      // Right-clicking the target box must resolve eager items and open the menu
      // without throwing.
      await _secondaryClick(tester, find.text('Target Box'));
      await tester.pumpAndSettle();

      expect(find.text('Eager Item 1'), findsOneWidget);
      expect(find.text('Lazy Item 1'), findsNothing);
    });

    testWidgets(
        'switches from items to itemsBuilder at runtime and invokes builder',
        (tester) async {
      final hostKey =
          material.GlobalKey<_DynamicContextMenuTestHostState>();

      await tester.pumpWidget(
        _testShell(
          child: _DynamicContextMenuTestHost(
            key: hostKey,
            initialItems: const [
              QueryaMenuItem(child: Text('Old Eager Item')),
            ],
            initialItemsBuilder: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      var builderCallCount = 0;

      // Switch to lazy itemsBuilder mode
      hostKey.currentState!.update(
        newItems: null,
        newItemsBuilder: (context) {
          builderCallCount++;
          return [
            const QueryaMenuItem(child: Text('New Lazy Item')),
          ];
        },
      );
      await tester.pumpAndSettle();

      expect(builderCallCount, 0);

      // Open context menu — should call itemsBuilder, not stale eager children
      await _secondaryClick(tester, find.text('Target Box'));
      await tester.pumpAndSettle();

      expect(builderCallCount, 1);
      expect(find.text('New Lazy Item'), findsOneWidget);
      expect(find.text('Old Eager Item'), findsNothing);
    });

    testWidgets('updates items when remaining in eager mode', (tester) async {
      final hostKey =
          material.GlobalKey<_DynamicContextMenuTestHostState>();

      await tester.pumpWidget(
        _testShell(
          child: _DynamicContextMenuTestHost(
            key: hostKey,
            initialItems: const [
              QueryaMenuItem(child: Text('Version 1 Item')),
            ],
            initialItemsBuilder: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      hostKey.currentState!.update(
        newItems: const [
          QueryaMenuItem(child: Text('Version 2 Item')),
        ],
        newItemsBuilder: null,
      );
      await tester.pumpAndSettle();

      await _secondaryClick(tester, find.text('Target Box'));
      await tester.pumpAndSettle();

      expect(find.text('Version 2 Item'), findsOneWidget);
      expect(find.text('Version 1 Item'), findsNothing);
    });
  });
}
