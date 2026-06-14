import 'dart:io';

/// Opens [directoryPath] in the platform file manager.
///
/// Creates the directory first when missing. Returns `false` when the platform
/// opener is unavailable or reports failure.
Future<bool> openDirectoryInFileManager(
  String directoryPath, {
  Future<bool> Function(String path)? opener,
}) async {
  final dir = Directory(directoryPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final open = opener ?? _defaultOpener;
  return open(directoryPath);
}

Future<bool> _defaultOpener(String path) async {
  try {
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [path]);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
      return true;
    }
    return false;
  } on Object {
    return false;
  }
}
