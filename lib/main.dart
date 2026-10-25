import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_wiring.dart';
import 'core/actions/querya_command_registry.dart';
import 'core/editor/syntax_highlight_service.dart';
import 'core/extensions/local_extension_registry.dart';
import 'core/layout/ui_scale_controller.dart';
import 'core/market/marketplace_selection.dart';
import 'core/mcp/mcp_server_controller.dart';
import 'core/motion/display_refresh_service.dart';
import 'core/motion/querya_motion_controller.dart';
import 'core/platform/file_launch_service.dart';
import 'core/platform/macos_file_open_channel.dart';
import 'core/security/ssl_certificate_support.dart';
import 'core/extensions/sandbox/sandbox_log_paths.dart';
import 'core/storage/local_db.dart';
import 'core/util/querya_log.dart';
import 'core/theme/theme_controller.dart';
import 'features/recovery/querya_startup_recovery_app.dart';
import 'features/updater/update_controller.dart';

void main([List<String> args = const []]) async {
  unawaited(runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installAppWiring();
    FileLaunchService.instance.processLaunchArguments(args);
    await MacOsFileOpenChannel.install();

    unawaited(SandboxLogPaths.logsDirectory()
        .then(QueryaLog.instance.init)
        .catchError((Object e) => debugPrint('QueryaLog: no log dir: $e')));
    QueryaLog.instance.info('app', 'start');

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
      QueryaLog.instance.error(
        'flutter',
        details.exceptionAsString(),
        stack: details.stack,
      );
    };

    DisplayRefreshService.initialize();
    await LocalDb.initFfi();

    try {
      await LocalDb.instance.open();
      await SyntaxHighlightService.ensureInitialized();
      await ThemeController.instance.load();
      await UiScaleController.instance.load();
      await QueryaMotionController.instance.load();
      QueryaCommandRegistry.instance.ensureCoreDefaults();
      unawaited(LocalExtensionRegistry.instance.load());
      await installMarketplaceRepository();
      unawaited(UpdateController.instance.initialize());
      unawaited(cleanupStaleMongoTlsTempFiles());
      unawaited(McpServerController.instance.startIfEnabled());
      runApp(const QueryaApp());
    } catch (error, stack) {
      debugPrint('Startup database initialization failed: $error\n$stack');
      QueryaLog.instance.error(
        'startup',
        'database initialization failed',
        error: error,
        stack: stack,
      );
      runApp(
        QueryaStartupRecoveryApp(
          error: error,
          stackTrace: stack,
        ),
      );
    }

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
    QueryaLog.instance.error('zone', 'unhandled async error',
        error: error, stack: stack);
  }));
}
