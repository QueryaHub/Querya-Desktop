import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

material.Widget _testShell({required material.Widget child}) {
  final td = QueryaTheme.darkDefault
      .toShadcnThemeData()
      .copyWith(platform: () => material.TargetPlatform.linux);
  return ShadcnApp(
    theme: td,
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

  final List<MenuItem>? initialItems;
  final List<MenuItem> Function(material.BuildContext)? initialItemsBuilder;

  @override
  State<_DynamicContextMenuTestHost> createState() =>
      _DynamicContextMenuTestHostState();
}

class _DynamicContextMenuTestHostState
    extends material.State<_DynamicContextMenuTestHost> {
  late List<MenuItem>? items = widget.initialItems;
  late List<MenuItem> Function(material.BuildContext)? itemsBuilder =
      widget.initialItemsBuilder;

  void update({
    List<MenuItem>? newItems,
    List<MenuItem> Function(material.BuildContext)? newItemsBuilder,
  }) {
    setState(() {
      items = newItems;
      itemsBuilder = newItemsBuilder;
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Center(
      child: ContextMenu(
        items: items,
        itemsBuilder: itemsBuilder,
        child: const material.Text('Target Box'),
      ),
    );
  }
}

void main() {
  group('ContextMenu mode switching (#1011)', () {
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
              const MenuButton(child: Text('Lazy Item 1')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to eager items without itemsBuilder
      hostKey.currentState!.update(
        newItems: [
          const MenuButton(child: Text('Eager Item 1')),
        ],
        newItemsBuilder: null,
      );
      await tester.pumpAndSettle();

      // Right-clicking the target box must resolve eager items and open the menu
      // without throwing "Null check operator used on a null value".
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
              MenuButton(child: Text('Old Eager Item')),
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
            const MenuButton(child: Text('New Lazy Item')),
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
              MenuButton(child: Text('Version 1 Item')),
            ],
            initialItemsBuilder: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      hostKey.currentState!.update(
        newItems: const [
          MenuButton(child: Text('Version 2 Item')),
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
