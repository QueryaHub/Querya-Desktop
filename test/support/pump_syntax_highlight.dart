import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/editor/querya_highlight_controller.dart';

/// Flushes the syntax-highlight debounce timer and pending isolate work.
Future<void> pumpSyntaxHighlightDebounce(WidgetTester tester) async {
  await tester.pump(kSyntaxHighlightDebounce);
  await tester.pump();
}
