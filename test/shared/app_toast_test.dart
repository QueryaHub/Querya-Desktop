import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('showAppToast renders feedback through the toast layer',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.TextButton(
            onPressed: () => showAppToast(
              context: context,
              message: 'Saved successfully',
              variant: AppToastVariant.success,
            ),
            child: const material.Text('Show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Saved successfully'), findsOneWidget);
    expect(find.byType(shadcn.Alert), findsOneWidget);
    expect(
      tester
          .widget<shadcn.ToastEntryLayout>(
            find.byType(shadcn.ToastEntryLayout),
          )
          .duration,
      QueryaMotion.standard,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('showAppToast disables entry motion with reduced OS motion',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) => material.MediaQuery(
            data: material.MediaQuery.of(context).copyWith(
              disableAnimations: true,
            ),
            child: material.Builder(
              builder: (context) => material.TextButton(
                onPressed: () => showAppToast(
                  context: context,
                  message: 'No motion',
                ),
                child: const material.Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(
      tester
          .widget<shadcn.ToastEntryLayout>(
            find.byType(shadcn.ToastEntryLayout),
          )
          .duration,
      const Duration(microseconds: 1),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
