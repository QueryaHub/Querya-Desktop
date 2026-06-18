import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/editor/syntax_highlight_service.dart';
import 'core/layout/ui_scale_controller.dart';
import 'core/motion/display_refresh_service.dart';
import 'core/motion/querya_motion_controller.dart';
import 'core/storage/local_db.dart';
import 'core/theme/theme_controller.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    DisplayRefreshService.initialize();
    await LocalDb.initFfi();
    await SyntaxHighlightService.ensureInitialized();
    await ThemeController.instance.load();
    await UiScaleController.instance.load();
    await QueryaMotionController.instance.load();
    runApp(const QueryaApp());
    doWhenWindowReady(() {
      final win = appWindow;
      win.minSize = const Size(900, 600);
      win.size = const Size(1280, 720);
      win.alignment = Alignment.center;
      win.title = 'Querya';
      win.show();
    });
  }, (error, stack) {
    debugPrint('Unhandled async error: $error\n$stack');
  });
}
