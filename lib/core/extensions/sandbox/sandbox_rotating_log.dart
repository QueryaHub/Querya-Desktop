import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Size-capped append-only log with simple rotation (Block E §6).
///
/// When the active file would exceed [maxBytes], it is renamed to `*.log.1`
/// and a fresh file is opened. At most [maxFiles] files are kept
/// (active + archives). Issue #304: ≤ 2 files per plugin.
class SandboxRotatingLog {
  SandboxRotatingLog({
    required this.file,
    this.maxBytes = 5 * 1024 * 1024,
    this.maxFiles = 2,
  }) : assert(maxFiles >= 1);

  final File file;
  final int maxBytes;
  final int maxFiles;

  Future<void> append(String text) async {
    if (text.isEmpty) return;
    await file.parent.create(recursive: true);
    await _rotateIfNeeded(utf8.encode(text).length);
    await file.writeAsString(text, mode: FileMode.append, flush: true);
  }

  Future<void> appendLine(String line) async {
    final normalized = line.endsWith('\n') ? line : '$line\n';
    await append(normalized);
  }

  Future<void> _rotateIfNeeded(int incomingBytes) async {
    if (!await file.exists()) return;
    final size = await file.length();
    if (size + incomingBytes <= maxBytes) return;

    // Shift older archives up: .1 → .2 → … → .(maxFiles-1), drop the oldest.
    for (var i = maxFiles - 1; i >= 2; i--) {
      final src = File('${file.path}.${i - 1}');
      final dst = File('${file.path}.$i');
      if (await dst.exists()) {
        await dst.delete();
      }
      if (await src.exists()) {
        await src.rename(dst.path);
      }
    }

    if (maxFiles == 1) {
      await file.delete();
      return;
    }

    final firstArchive = File('${file.path}.1');
    if (await firstArchive.exists()) {
      await firstArchive.delete();
    }
    await file.rename(firstArchive.path);
  }

  static String archivePath(File active, int index) =>
      p.join(active.parent.path, '${p.basename(active.path)}.$index');
}
