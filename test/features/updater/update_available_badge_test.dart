import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/updater/update_available_badge.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  late UpdateController controller;

  setUp(() {
    controller = UpdateController();
    controller.resetForTest();
  });

  tearDown(() {
    controller.resetForTest();
    controller.dispose();
  });

  testWidgets('pulse ticker runs only while badge is visible', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: material.Scaffold(
            body: UpdateAvailableBadge(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    var state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(find.textContaining('available'), findsNothing);
    expect(state.isPulseAnimating, isFalse);

    controller.setPendingUpdate(
      const UpdateManifest(
        version: '9.9.9',
        changelog: '',
        assets: [],
      ),
    );
    await tester.pump();
    state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(find.textContaining('v9.9.9 available'), findsOneWidget);
    expect(state.isPulseAnimating, isTrue);

    controller.setPendingUpdate(null);
    await tester.pump();
    state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(find.textContaining('available'), findsNothing);
    expect(state.isPulseAnimating, isFalse);
  });

  testWidgets('motion off does not pulse', (tester) async {
    controller.setPendingUpdate(
      const UpdateManifest(
        version: '1.0.0',
        changelog: '',
        assets: [],
      ),
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.off,
          child: material.Scaffold(
            body: UpdateAvailableBadge(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(find.textContaining('v1.0.0 available'), findsOneWidget);
    expect(state.isPulseAnimating, isFalse);
  });

  testWidgets('reduced motion pulses at half period', (tester) async {
    controller.setPendingUpdate(
      const UpdateManifest(
        version: '2.0.0',
        changelog: '',
        assets: [],
      ),
    );

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.reduced,
          child: material.Scaffold(
            body: UpdateAvailableBadge(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(find.textContaining('v2.0.0 available'), findsOneWidget);
    expect(state.isPulseAnimating, isTrue);
    expect(
      state.pulseDuration,
      Duration(microseconds: kUpdateBadgePulsePeriod.inMicroseconds ~/ 2),
    );
  });

  testWidgets('pulse is finite: settles and stays idle (#1554)',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: QueryaMotionScope(
          level: QueryaMotionLevel.full,
          child: material.Scaffold(
            body: UpdateAvailableBadge(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    const manifest = UpdateManifest(
      version: '3.0.0',
      changelog: '',
      assets: [],
    );
    controller.setPendingUpdate(manifest);
    await tester.pump();

    final state = tester.state<UpdateAvailableBadgeState>(
      find.byType(UpdateAvailableBadge),
    );
    expect(state.isPulseAnimating, isTrue);

    await tester.pump(
      kUpdateBadgePulsePeriod * kUpdateBadgePulseLegs +
          const Duration(milliseconds: 100),
    );
    await tester.pump();
    expect(state.isPulseAnimating, isFalse);
    expect(find.textContaining('v3.0.0 available'), findsOneWidget);

    // Another sync (controller notification, dependency change) must not
    // start the pulse again for the same pending update.
    controller.setPendingUpdate(manifest);
    await tester.pump();
    expect(state.isPulseAnimating, isFalse);

    // A later update pulses again once the badge went away in between.
    controller.setPendingUpdate(null);
    await tester.pump();
    controller.setPendingUpdate(manifest);
    await tester.pump();
    expect(state.isPulseAnimating, isTrue);
  });
}
