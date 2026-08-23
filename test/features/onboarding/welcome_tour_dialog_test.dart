import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/onboarding/welcome_tour_dialog.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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

  testWidgets('WelcomeTourDialog displays steps and allows navigation through all 4 slides',
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
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Connect in Seconds'), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_skip_button')), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_next_button')), findsOneWidget);

    // Click Next -> Slide 2
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('Fluid Sidebar & Navigation'), findsOneWidget);
    expect(find.byKey(const Key('welcome_tour_prev_button')), findsOneWidget);

    // Click Next -> Slide 3
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.text('Interactive SQL & 2D Grid'), findsOneWidget);

    // Click Next -> Slide 4
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Zero-Trust Security & Playground'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Click Back -> Slide 3
    await tester.tap(find.byKey(const Key('welcome_tour_prev_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.text('Interactive SQL & 2D Grid'), findsOneWidget);
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

    // Advance to slide 4
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome_tour_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4'), findsOneWidget);
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
}
