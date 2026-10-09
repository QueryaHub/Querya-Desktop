import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/main_screen.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';

import '../../memory_secrets_backend.dart';
import '../../support/local_db_test_support.dart';
import '../../support/querya_theme_test_shell.dart';

/// Boots an isolated Querya shell for end-to-end widget tests: a throw-away
/// data directory, an empty [LocalDb], in-memory secrets and a virtual screen.
///
/// ```dart
/// final app = E2eAppHarness();
/// setUpAll(app.setUpAll);
/// tearDownAll(app.tearDownAll);
///
/// testWidgets('opens', (tester) async {
///   await app.launch(tester);
///   expect(find.byType(MainScreen), findsOneWidget);
/// });
/// ```
class E2eAppHarness {
  E2eAppHarness({this.prefix = 'querya_e2e_'});

  final String prefix;
  Directory? _dir;

  /// Isolated data directory of this run (valid after [setUpAll]).
  Directory get dataDir => _dir!;

  /// Creates the isolated data directory and opens the database.
  Future<void> setUpAll() async {
    _dir = await initTestLocalDb(prefix);
    AppDataRoot.mockInstallDirectory = _dir!.path;
    AppDataRoot.mockEnvironment = {'QUERYA_PORTABLE': '1'};
    QueryaWindowTitleBar.useNativeWindowChrome = false;
    testMemorySecrets.clear();
  }

  Future<void> tearDownAll() async {
    QueryaWindowTitleBar.useNativeWindowChrome = true;
    AppDataRoot.resetMocks();
    final dir = _dir;
    if (dir != null) await disposeTestLocalDb(dir);
  }

  /// Pumps the main screen at [size] (logical pixels) and lets it settle.
  Future<void> launch(
    WidgetTester tester, {
    material.Size size = const material.Size(1400, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.SizedBox(
          width: size.width,
          height: size.height,
          child: const MainScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Pumps until animations finish, tolerating perpetual spinners.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts the app and lets pending timers fire, so the test can finish
  /// without "Timer is still pending" failures. Call at the end of a scenario.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const material.SizedBox.shrink());
    // Let the database requests still in flight finish in real time first.
    // Advancing the fake clock in 10 s steps while one is pending fires
    // sqflite's "database has been locked" warning, which is noise here: the
    // app holds no lock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
  }

  /// Removes every connection so tests do not leak into each other.
  Future<void> resetData(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final c in await LocalDb.instance.getConnections()) {
        if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
      }
    });
  }
}
