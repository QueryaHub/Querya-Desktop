import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/platform/open_directory.dart';
import 'package:querya_desktop/core/util/diagnostics_report.dart';
import 'package:querya_desktop/core/util/querya_log.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';

/// How many log lines [copyDiagnostics] puts in the report.
const diagnosticsLogLines = 200;

/// Help > Open logs folder.
Future<void> openLogsFolder(BuildContext context) async {
  final dir =
      QueryaLog.instance.directory ?? await SandboxLogPaths.logsDirectory();
  final opened = await openDirectoryInFileManager(dir.path);
  if (!opened && context.mounted) {
    showAppToast(
      context: context,
      variant: AppToastVariant.error,
      message: 'Could not open the logs folder: ${dir.path}',
    );
  }
}

/// Help > Copy diagnostics: version, OS and the end of the log to the clipboard.
Future<void> copyDiagnostics(BuildContext context) async {
  String version;
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {
    version = 'unknown';
  }
  final report = buildDiagnosticsReport(
    appVersion: version,
    operatingSystem: Platform.operatingSystem,
    operatingSystemVersion: Platform.operatingSystemVersion,
    dartVersion: Platform.version.split(' ').first,
    logLines: await QueryaLog.instance.tail(diagnosticsLogLines),
  );
  await Clipboard.setData(ClipboardData(text: report));
  if (context.mounted) {
    showAppToast(
      context: context,
      variant: AppToastVariant.success,
      message: 'Diagnostics copied to the clipboard.',
    );
  }
}
