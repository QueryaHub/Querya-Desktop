import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/platform/file_launch_service.dart';

/// Files Finder hands to the app: "Open With" and a double-click (#1589).
///
/// macOS delivers them as an Open Documents Apple Event, not in `argv`, so
/// [FileLaunchService.processLaunchArguments] never saw them. `AppDelegate`
/// keeps the ones that arrive before Dart asks ([takeLaunchFiles]) and then
/// sends each later batch over this channel.
abstract final class MacOsFileOpenChannel {
  static const channel = MethodChannel('querya/file_open');

  /// Starts listening and takes the files that arrived during launch. A
  /// no-op off macOS.
  static Future<void> install() async {
    if (!Platform.isMacOS) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') queuePaths(call.arguments);
      return null;
    });
    try {
      queuePaths(await channel.invokeListMethod<String>('takePendingFiles'));
    } on MissingPluginException {
      // A runner without the channel (older build): only argv works.
    } on PlatformException catch (e) {
      debugPrint('MacOsFileOpenChannel: $e');
    }
  }

  /// Adds the paths in [arguments] (a list of strings) that the app can open
  /// as pending launch targets; returns how many were added.
  @visibleForTesting
  static int queuePaths(Object? arguments) {
    if (arguments is! List) return 0;
    var added = 0;
    for (final path in arguments) {
      if (path is! String) continue;
      final target = FileLaunchService.parseArgument(path);
      if (target == null) continue;
      FileLaunchService.instance.addPendingTarget(target);
      added++;
    }
    return added;
  }
}
