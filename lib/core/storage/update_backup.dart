import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies of the local database made before an in-app update (#1497).
///
/// An update can bring a newer database schema, and a later downgrade (a
/// beta promoted to an older stable, or an older build installed by hand)
/// cannot read it. The copy next to the database is the way back.
abstract final class UpdateBackup {
  /// How many pre-update copies are kept; older ones are deleted.
  static const keep = 3;

  /// `querya.db.pre-<from>-<to>.bak` next to [dbPath].
  static String pathFor(String dbPath, String fromVersion, String toVersion) {
    String safe(String v) => v.replaceAll(RegExp(r'[^0-9A-Za-z.+-]'), '_');
    return '$dbPath.pre-${safe(fromVersion)}-${safe(toVersion)}.bak';
  }

  /// Copies [dbPath] (and its `-wal`, if any) to [pathFor] and deletes all but
  /// the newest [keep] copies. The database must be closed. Returns the copy.
  static Future<String> create({
    required String dbPath,
    required String fromVersion,
    required String toVersion,
    int keep = UpdateBackup.keep,
  }) async {
    final db = File(dbPath);
    if (!await db.exists()) {
      throw FileSystemException('Database file does not exist', dbPath);
    }
    final backup = pathFor(dbPath, fromVersion, toVersion);
    await db.copy(backup);
    final wal = File('$dbPath-wal');
    final backupWal = File('$backup-wal');
    if (await wal.exists()) {
      await wal.copy(backupWal.path);
    } else if (await backupWal.exists()) {
      await backupWal.delete(); // from an earlier copy with the same name
    }
    // A copy made just now is the newest even when the clock is coarse.
    await File(backup).setLastModified(DateTime.now());
    await prune(dbPath, keep: keep);
    return backup;
  }

  /// The pre-update copies of [dbPath], newest first.
  static Future<List<File>> list(String dbPath) async {
    final dir = Directory(p.dirname(dbPath));
    final prefix = '${p.basename(dbPath)}.pre-';
    final copies = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is File && name.startsWith(prefix) && name.endsWith('.bak')) {
        copies.add(e);
      }
    }
    final stamps = {for (final f in copies) f.path: await f.lastModified()};
    copies.sort((a, b) => stamps[b.path]!.compareTo(stamps[a.path]!));
    return copies;
  }

  /// Deletes all but the newest [keep] copies, with their `-wal` files.
  static Future<void> prune(String dbPath, {int keep = UpdateBackup.keep}) async {
    final copies = await list(dbPath);
    for (final old in copies.skip(keep)) {
      await old.delete();
      final wal = File('${old.path}-wal');
      if (await wal.exists()) await wal.delete();
    }
  }
}
