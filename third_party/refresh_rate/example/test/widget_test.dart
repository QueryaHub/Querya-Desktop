import 'package:flutter_test/flutter_test.dart';

import 'package:refresh_rate_example/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RefreshRateExampleApp());
    expect(find.text('Diagnostic Console'), findsOneWidget);
    expect(find.text('Display Info'), findsOneWidget);
  });
}
