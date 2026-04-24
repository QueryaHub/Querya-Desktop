import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';

void main() {
  testWidgets('showAppDialog presents builder child and can be dismissed',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showAppDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (c) => const AlertDialog(title: Text('Dialog title')),
    );

    await tester.pump();
    expect(find.text('Dialog title'), findsOneWidget);

    Navigator.of(ctx, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await future;
  });

  testWidgets('showAppDialog uses BackdropFilter on scaffold', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    showAppDialog<void>(
      context: ctx,
      builder: (c) => const SimpleDialog(title: Text('X')),
    );
    await tester.pump();
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
