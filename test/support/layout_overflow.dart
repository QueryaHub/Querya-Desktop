import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// True if [FlutterErrorDetails] describe a RenderFlex / layout overflow.
bool isLayoutOverflowError(FlutterErrorDetails details) {
  final s = details.exceptionAsString();
  return s.contains('overflowed') ||
      s.contains('Overflow') ||
      s.contains('RenderFlex');
}

/// Bounded frame pumping — avoids [WidgetTester.pumpAndSettle], which never returns
/// when the tree has a never-ending animation (e.g. [CircularProgressIndicator],
/// shimmer, or a continuous implicit animation).
Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 120,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}

/// Pumps [widget] with [tester.binding.setSurfaceSize], restores size in tearDown.
Future<void> pumpWidgetWithSurfaceSize(
  WidgetTester tester,
  Size size,
  Widget widget,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await pumpFrames(tester);
}

/// Runs [action], collecting overflow-like [FlutterErrorDetails] while still
/// forwarding all errors to the previous [FlutterError.onError].
Future<List<FlutterErrorDetails>> collectOverflowErrorsDuring(
  Future<void> Function() action,
) async {
  final overflows = <FlutterErrorDetails>[];
  final old = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (isLayoutOverflowError(details)) {
      overflows.add(details);
    }
    old?.call(details);
  };
  try {
    await action();
  } finally {
    FlutterError.onError = old;
  }
  return overflows;
}

/// Fails the test if any layout overflow was reported during [action].
Future<void> expectNoLayoutOverflow(Future<void> Function() action) async {
  final overflows = await collectOverflowErrorsDuring(action);
  expect(
    overflows,
    isEmpty,
    reason: overflows.isEmpty
        ? null
        : overflows.map((e) => e.exceptionAsString()).join('\n---\n'),
  );
}
