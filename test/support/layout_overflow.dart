import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// True if [FlutterErrorDetails] describe a RenderFlex / layout overflow.
bool isLayoutOverflowError(FlutterErrorDetails details) {
  final s = details.exceptionAsString();
  return s.contains('overflowed') ||
      s.contains('Overflow') ||
      s.contains('RenderFlex');
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
  await tester.pumpAndSettle();
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
