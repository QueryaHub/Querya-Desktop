import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app_lifecycle_cleanup.dart';

void main() {
  testWidgets('AppLifecycleCleanup renders child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLifecycleCleanup(
          child: Text('wrapped'),
        ),
      ),
    );
    expect(find.text('wrapped'), findsOneWidget);
  });

  testWidgets('AppLifecycleCleanup disposes without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLifecycleCleanup(
          child: SizedBox(),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox.shrink()),
    );
    await tester.pump();
  });
}
