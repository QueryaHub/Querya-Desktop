import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app.dart';

void main() {
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
