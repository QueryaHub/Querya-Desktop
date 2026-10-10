import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';

void main() {
  // Headless tests have no native bitsdojo symbols.
  setUp(() => QueryaWindowTitleBar.useNativeWindowChrome = false);
  tearDown(() => QueryaWindowTitleBar.useNativeWindowChrome = true);

  testWidgets('QueryaApp build is pure and does not crash or throw', (tester) async {
    await tester.pumpWidget(
      const QueryaApp(),
    );
    // Rebuilding the root widget is idempotent and doesn't trigger side effects
    await tester.pumpWidget(
      const QueryaApp(),
    );
    expect(find.byType(QueryaApp), findsOneWidget);
  });
}
