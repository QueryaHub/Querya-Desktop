import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../security/archive_path_guard.dart';
import '../../security/safe_zip_extractor.dart';
import '../app_updater_service.dart';

/// Safely extracts a zip archive into [destinationDir].
Future<void> extractZipSecurely({
  required File zipFile,
  required Directory destinationDir,
}) async {
  if (await destinationDir.exists()) {
    await destinationDir.delete(recursive: true);
  }
  await destinationDir.create(recursive: true);

  final Archive archive;
  try {
    archive = await SafeZipExtractor.readAndDecodeFile(zipFile);
  } on SafeZipException catch (error) {
    throw AppUpdaterException(error.message);
  }
  final root = p.normalize(destinationDir.path);

  for (final entry in archive) {
    final name = entry.name;
    if (!isArchiveEntryNameSafe(name)) {
      throw AppUpdaterException(
        'Security violation: path traversal in archive entry "$name"',
      );
    }

    final targetPath = p.normalize(p.join(root, name));
    if (!isArchiveExtractPathWithinRoot(root, targetPath)) {
      throw AppUpdaterException(
        'Security violation: extraction path out of bounds "$name"',
      );
    }

    if (entry.isFile) {
      final out = File(targetPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>);
    } else {
      await Directory(targetPath).create(recursive: true);
    }
  }
}

/// Finds the first `.AppImage` file inside [directory].
Future<File?> findAppImageInDirectory(Directory directory) async {
  if (!await directory.exists()) return null;
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.appimage')) {
      return entity;
    }
  }
  return null;
}

/// Finds the first `.app` bundle directory inside [directory].
Future<Directory?> findMacAppBundleInDirectory(Directory directory) async {
  if (!await directory.exists()) return null;
  await for (final entity in directory.list(recursive: false)) {
    if (entity is Directory && entity.path.endsWith('.app')) {
      return entity;
    }
  }
  await for (final entity in directory.list(recursive: true)) {
    if (entity is Directory && p.basename(entity.path).endsWith('.app')) {
      return entity;
    }
  }
  return null;
}

/// Launches [scriptPath] detached from the current process tree.
Future<void> launchDetachedScript(String scriptPath, List<String> args) async {
  if (Platform.isWindows) {
    await Process.start(
      'cmd.exe',
      ['/c', scriptPath, ...args],
      mode: ProcessStartMode.detached,
    );
    return;
  }

  await Process.run('chmod', ['+x', scriptPath]);
  await Process.start(
    '/bin/sh',
    [scriptPath, ...args],
    mode: ProcessStartMode.detached,
  );
}

/// Shell script that waits for [pid], syncs [sourceDir] into [targetDir], then execs [executable].
String buildLinuxBundleReplaceScript({
  required int pid,
  required String sourceDir,
  required String targetDir,
  required String executable,
}) {
  return '''
#!/bin/sh
set -e
PID="$pid"
SRC='${_shellQuote(sourceDir)}'
DST='${_shellQuote(targetDir)}'
EXE='${_shellQuote(executable)}'
while kill -0 "\$PID" 2>/dev/null; do sleep 0.2; done
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "\$SRC"/ "\$DST"/
else
  rm -rf "\$DST"/*
  cp -a "\$SRC"/. "\$DST"/
fi
chmod +x "\$EXE" 2>/dev/null || true
rm -f "\$0"
exec "\$EXE"
''';
}

String buildLinuxAppImageReplaceScript({
  required int pid,
  required String targetAppImage,
  required String stagedAppImage,
}) {
  return '''
#!/bin/sh
set -e
PID="$pid"
TARGET='${_shellQuote(targetAppImage)}'
STAGED='${_shellQuote(stagedAppImage)}'
while kill -0 "\$PID" 2>/dev/null; do sleep 0.2; done
mv "\$TARGET" "\$TARGET.old" 2>/dev/null || true
mv "\$STAGED" "\$TARGET"
chmod +x "\$TARGET"
rm -f "\$0"
exec "\$TARGET"
''';
}

String buildWindowsReplaceBatch({
  required int pid,
  required String sourceDir,
  required String targetDir,
  required String executable,
}) {
  return '''
@echo off
set PID=$pid
set "SRC=$sourceDir"
set "DST=$targetDir"
set "EXE=$targetDir\\$executable"
:wait
tasklist /FI "PID eq %PID%" 2>NUL | find "%PID%" >NUL
if %ERRORLEVEL%==0 (
  timeout /t 1 /nobreak >NUL
  goto wait
)
xcopy /E /Y /I "%SRC%\\*" "%DST%\\"
start "" "%EXE%"
del "%~f0"
''';
}

String buildMacAppReplaceScript({
  required int pid,
  required String newAppBundle,
  required String targetAppBundle,
  required String executable,
}) {
  return '''
#!/bin/sh
set -e
PID="$pid"
NEW='${_shellQuote(newAppBundle)}'
TARGET='${_shellQuote(targetAppBundle)}'
EXE='${_shellQuote(executable)}'
while kill -0 "\$PID" 2>/dev/null; do sleep 0.2; done
rm -rf "\$TARGET.old" 2>/dev/null || true
mv "\$TARGET" "\$TARGET.old" 2>/dev/null || true
cp -R "\$NEW" "\$TARGET"
chmod +x "\$EXE" 2>/dev/null || true
rm -f "\$0"
open "\$TARGET"
''';
}

String _shellQuote(String value) => value.replaceAll("'", "'\\''");
