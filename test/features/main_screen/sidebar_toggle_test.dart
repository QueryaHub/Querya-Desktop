import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';
import 'package:querya_desktop/core/storage/app_data_root.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/querya_window_title_bar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_sidebar_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    AppDataRoot.resetMocks();
    AppDataRoot.mockInstallDirectory = tempDir.path;
    AppDataRoot.mockEnvironment = {'QUERYA_PORTABLE': '1'};
    QueryaWindowTitleBar.useNativeWindowChrome = false;
  });

  tearDown(() async {
    QueryaWindowTitleBar.useNativeWindowChrome = true;
    AppDataRoot.resetMocks();
    try {
      await LocalDb.instance.close();
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Fluid Collapsible Sidebar (#557)', () {
    test('AppSettings preserves sidebarVisible across sets and gets',
        () async {
      expect(await AppSettings.instance.getSidebarVisible(), isTrue);

      await AppSettings.instance.setSidebarVisible(false);
      expect(await AppSettings.instance.getSidebarVisible(), isFalse);

      await AppSettings.instance.setSidebarVisible(true);
      expect(await AppSettings.instance.getSidebarVisible(), isTrue);
    });

    testWidgets('title bar sidebar button reflects visibility and fires toggle',
        (tester) async {
      var toggleCount = 0;
      var isVisible = true;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.StatefulBuilder(
            builder: (context, setState) {
              return material.SizedBox(
                width: 800,
                child: QueryaWindowTitleBar(
                  onNewDatabaseConnection: () async {},
                  onNewDatabaseConnectionFromUrl: () async {},
                  isSidebarVisible: isVisible,
                  onToggleSidebar: () {
                    toggleCount++;
                    setState(() {
                      isVisible = !isVisible;
                    });
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final button = find.byKey(const Key('title_bar_toggle_sidebar_button'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(toggleCount, 1);
      expect(isVisible, isFalse);

      await tester.tap(button);
      await tester.pump();

      expect(toggleCount, 2);
      expect(isVisible, isTrue);
    });

    testWidgets('QueryaSpringController smoothly collapses and expands width',
        (tester) async {
      late QueryaSpringController controller;

      await tester.pumpWidget(
        material.MaterialApp(
          home: _SpringTestHost(
            initialWidth: 260,
            onCreated: (c) => controller = c,
          ),
        ),
      );
      await tester.pump();

      expect(controller.value, 260);
      expect(controller.isAnimating, isFalse);

      // Animate collapse to 0
      controller.animateTo(0);
      await tester.pump();
      expect(controller.isAnimating, isTrue);

      // Step animation forward
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.value, lessThan(260));
      expect(controller.value, greaterThan(0));

      // Step until settled
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(controller.value, closeTo(0, 0.01));
      expect(controller.isAnimating, isFalse);

      // Animate expand back to 260
      controller.animateTo(260);
      await tester.pump();
      expect(controller.isAnimating, isTrue);

      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(controller.value, closeTo(260, 0.01));
      expect(controller.isAnimating, isFalse);
    });
  });
}

class _SpringTestHost extends StatefulWidget {
  const _SpringTestHost({
    required this.initialWidth,
    required this.onCreated,
  });

  final double initialWidth;
  final ValueChanged<QueryaSpringController> onCreated;

  @override
  State<_SpringTestHost> createState() => _SpringTestHostState();
}

class _SpringTestHostState extends State<_SpringTestHost>
    with SingleTickerProviderStateMixin {
  late final QueryaSpringController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QueryaSpringController(
      vsync: this,
      value: widget.initialWidth,
      spring: QueryaSpring.gentle,
    );
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return SizedBox(
          width: _controller.value,
          height: 400,
        );
      },
    );
  }
}
