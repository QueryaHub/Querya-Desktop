import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/extensions/extension_driver_recovery_banner.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  testWidgets('ExtensionDriverRecoveryBanner renders and triggers onRestart callback', (tester) async {
    var restartClicked = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: ExtensionDriverRecoveryBanner(
          onRestart: () {
            restartClicked = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver Process Terminated or Unresponsive'), findsOneWidget);
    expect(find.text('Restart Driver'), findsOneWidget);

    await tester.tap(find.text('Restart Driver'));
    await tester.pumpAndSettle();

    expect(restartClicked, isTrue);
  });

  testWidgets('ExtensionDriverRecoveryBanner displays custom message and restarting spinner', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const ExtensionDriverRecoveryBanner(
          onRestart: _noop,
          isRestarting: true,
          customMessage: 'Custom crash diagnostic message',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Custom crash diagnostic message'), findsOneWidget);
    expect(find.text('Restarting...'), findsOneWidget);
    expect(find.byType(material.CircularProgressIndicator), findsOneWidget);
  });
}

void _noop() {}
