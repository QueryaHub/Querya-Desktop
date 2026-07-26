import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/querya_drag_settle.dart';

void main() {
  testWidgets('dragTo tracks 1:1 without spring lag', (tester) async {
    late QueryaDragSettleController controller;
    await tester.pumpWidget(
      _Host(onCreated: (c) => controller = c),
    );

    controller.dragTo(0.4);
    expect(controller.value, 0.4);
    expect(controller.isSettling, isFalse);
    controller.dragTo(0.55);
    expect(controller.value, 0.55);
  });

  testWidgets('settle with velocity soft-stops via spring', (tester) async {
    late QueryaDragSettleController controller;
    await tester.pumpWidget(
      _Host(onCreated: (c) => controller = c),
    );

    controller.dragTo(0.5);
    controller.settle(velocity: 1.2, useSprings: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isSettling, isTrue);
    // Velocity pushes past the release point briefly.
    expect(controller.value, isNot(0.5));

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(controller.value, closeTo(0.5, 0.05));
    expect(controller.isSettling, isFalse);
  });

  testWidgets('settle without springs snaps', (tester) async {
    late QueryaDragSettleController controller;
    await tester.pumpWidget(
      _Host(onCreated: (c) => controller = c),
    );

    controller.dragTo(0.62);
    controller.settle(velocity: 2, useSprings: false);
    expect(controller.value, 0.62);
    expect(controller.isSettling, isFalse);
  });

  testWidgets('drag mid-settle cancels animation', (tester) async {
    late QueryaDragSettleController controller;
    await tester.pumpWidget(
      _Host(onCreated: (c) => controller = c),
    );

    controller.dragTo(0.5);
    controller.settle(velocity: 1.5, useSprings: true);
    await tester.pump(const Duration(milliseconds: 20));
    controller.dragTo(0.7);
    expect(controller.value, 0.7);
    expect(controller.isSettling, isFalse);
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onCreated});

  final ValueChanged<QueryaDragSettleController> onCreated;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final QueryaDragSettleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QueryaDragSettleController(vsync: this, value: 0.5);
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
