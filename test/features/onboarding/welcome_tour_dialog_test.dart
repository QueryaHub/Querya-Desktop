import 'package:flutter/widgets.dart';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;

  @override
  Future<String?> getApplicationCachePath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_welcome_tour_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('WelcomeTourDialog displays steps and allows navigation through all 6 slides',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.Scaffold(
          body: WelcomeTourDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Slide 1: Connect in Seconds
    expect(find.text('Welcome to Querya'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);
    expect(find.text('Connect in Seconds'), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_skip_button')), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_next_button')), findsOneWidget);

    // Click Next -> Slide 2
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 6'), findsOneWidget);
    expect(find.text('Fluid Sidebar & Navigation'), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_prev_button')), findsOneWidget);

    // Click Next -> Slide 3
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 6'), findsOneWidget);
    expect(find.text('Pro SQL Editor & Workspaces'), findsOneWidget);

    // Click Next -> Slide 4
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 6'), findsOneWidget);
    expect(find.text('Interactive 2D Grid & DML Staging'), findsOneWidget);

    // Click Next -> Slide 5
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 5 of 6'), findsOneWidget);
    expect(find.text('Compound Filter Bar & Quick Calc'), findsOneWidget);

    // Click Next -> Slide 6 (Hotkeys Matrix)
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 6 of 6'), findsOneWidget);
    expect(find.text('Keyboard Shortcuts Cheat Sheet'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Click Back -> Slide 5
    await tester.tap(find.byKey(const Key('welcome_tour_prev_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 5 of 6'), findsOneWidget);
    expect(find.text('Compound Filter Bar & Quick Calc'), findsOneWidget);
  });

  testWidgets('Back slides the earlier step in from the left (#1645)',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.Scaffold(body: WelcomeTourDialog()),
      ),
    );
    await tester.pumpAndSettle();

    double dxOf(int step) => tester
        .widget<material.SlideTransition>(
          find
              .ancestor(
                of: find.byKey(ValueKey(step)),
                matching: find.byType(material.SlideTransition),
              )
              .first,
        )
        .position
        .value
        .dx;

    // Forward: the new step comes from the right, the old one leaves left.
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(dxOf(1), greaterThan(0));
    expect(dxOf(0), lessThan(0));
    await tester.pumpAndSettle();

    // Back: mirrored.
    await tester.tap(find.byKey(const Key('welcome_tour_prev_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(dxOf(0), lessThan(0));
    expect(dxOf(1), greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 6'), findsOneWidget);
  });

  testWidgets('WelcomeTourDialog launches demo playground on action button tap',
      (tester) async {
    var demoLaunched = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: WelcomeTourDialog(
            onLaunchDemo: () => demoLaunched = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Advance to slide 6 (Playground & Hotkeys)
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Step 6 of 6'), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_demo_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('welcome_tour_demo_button')));
    await tester.pumpAndSettle();

    expect(demoLaunched, isTrue);
  });

  testWidgets('WelcomeTourDialog handles Skip button and dismisses dialog',
      (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const material.Scaffold(
          body: WelcomeTourDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcome_tour_skip_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome_tour_skip_button')));
    await tester.pumpAndSettle();
  });

  testWidgets('WelcomeTourDialog exposes Home buttons and triggers onGoHome',
      (tester) async {
    var homeTriggered = false;

    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Scaffold(
          body: WelcomeTourDialog(
            onGoHome: () => homeTriggered = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcome_tour_home_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome_tour_home_button')));
    await tester.pumpAndSettle();

    expect(homeTriggered, isTrue);
  });

  testWidgets('Motion Off makes welcome tour chrome instant', (tester) async {
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: const QueryaMotionScope(
          level: QueryaMotionLevel.off,
          child: material.Scaffold(
            body: WelcomeTourDialog(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<material.AnimatedSize>(find.byType(material.AnimatedSize)).duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<material.AnimatedSwitcher>(find.byType(material.AnimatedSwitcher))
          .duration,
      Duration.zero,
    );
  });

  testWidgets('slide icons and shortcut badges adapt to theme tokens (#1509)',
      (tester) async {
    const lightTheme = QueryaTheme.lightDefault;
    await tester.pumpWidget(
      queryaThemeTestShell(
        data: lightTheme,
        child: const material.Scaffold(
          body: WelcomeTourDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Slide 1: Connect in Seconds icon uses lightTheme.workbench.accent
    final hubIconFinder = find.byIcon(material.Icons.hub_rounded);
    expect(hubIconFinder, findsOneWidget);
    final hubIcon = tester.widget<material.Icon>(hubIconFinder);
    expect(hubIcon.color, lightTheme.workbench.accent);

    // KbdBadge uses lightTheme.workbench.surface
    final containerFinder = find.ancestor(
      of: find.text('N'),
      matching: find.byType(material.Container),
    );
    final keycapContainer = tester.widget<material.Container>(containerFinder.first);
    final boxDecoration = keycapContainer.decoration! as material.BoxDecoration;
    expect(boxDecoration.color, lightTheme.workbench.surface);

    // Next -> Slide 2: Fluid Sidebar uses lightTheme.colors.chart4
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    final sidebarIconFinder = find.byIcon(material.Icons.view_sidebar_rounded);
    expect(sidebarIconFinder, findsOneWidget);
    final sidebarIcon = tester.widget<material.Icon>(sidebarIconFinder);
    expect(sidebarIcon.color, lightTheme.colors.chart4);
  });
}
