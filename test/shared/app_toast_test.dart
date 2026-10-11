import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';

import '../support/querya_theme_test_shell.dart';

material.Widget _app({
  required void Function(material.BuildContext) onShow,
  bool disableAnimations = false,
}) {
  return queryaThemeTestShell(
    child: material.Builder(
      builder: (context) => material.MediaQuery(
        data: material.MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
        ),
        child: material.Builder(
          builder: (context) => material.TextButton(
            onPressed: () => onShow(context),
            child: const material.Text('Show'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a toast shows its message and closes itself', (tester) async {
    await tester.pumpWidget(
      _app(
        onShow: (context) => showAppToast(
          context: context,
          message: 'Saved successfully',
          variant: AppToastVariant.success,
          showDuration: const Duration(seconds: 2),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Saved successfully'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Saved successfully'), findsNothing);
  });

  testWidgets('the close button dismisses a toast', (tester) async {
    await tester.pumpWidget(
      _app(
        onShow: (context) => showAppToast(context: context, message: 'Heads up'),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Heads up'), findsOneWidget);

    await tester.tap(find.byIcon(material.Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Heads up'), findsNothing);
  });

  testWidgets('toasts stack instead of overlapping', (tester) async {
    await tester.pumpWidget(
      _app(
        onShow: (context) {
          showAppToast(context: context, message: 'First');
          showAppToast(context: context, message: 'Second');
        },
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final first = tester.getRect(find.text('First'));
    final second = tester.getRect(find.text('Second'));
    expect(first.bottom, lessThanOrEqualTo(second.top));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion shows the toast fully on the first frame',
      (tester) async {
    await tester.pumpWidget(
      _app(
        disableAnimations: true,
        onShow: (context) => showAppToast(context: context, message: 'No motion'),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final opacity = tester.widget<material.Opacity>(
      find
          .ancestor(
            of: find.text('No motion'),
            matching: find.byType(material.Opacity),
          )
          .first,
    );
    expect(opacity.opacity, 1);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
