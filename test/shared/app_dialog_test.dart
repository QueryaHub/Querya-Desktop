import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';

void main() {
  testWidgets('barrierDismissible true closes dialog on backdrop tap',
      (tester) async {
    late BuildContext ctx;
    var completed = false;
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
    ).whenComplete(() => completed = true);

    await tester.pumpAndSettle();
    expect(find.text('Dialog title'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Dialog title'), findsNothing);
    expect(completed, isTrue);
    await future;
  });

  testWidgets('barrierDismissible false ignores backdrop tap', (tester) async {
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
      barrierDismissible: false,
      builder: (c) => const AlertDialog(title: Text('Blocking dialog')),
    );

    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Blocking dialog'), findsOneWidget);

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
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsWidgets);
  });
}
