import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';

/// Folders: names, order, and which connection sits in which.
/// Part of [LocalDb], which keeps the same methods and delegates here.
class FolderRepository {
  FolderRepository(this._open);

  final Future<Database> Function() _open;

  Future<List<String>> getFolders() async {
    final db = await _open();
    final rows = await db.query('folders', orderBy: 'sort_order ASC, name ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> addFolder(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final db = await _open();
    await db.insert('folders', {'name': n});
  }

  /// Removes the folder; its connections stay, without a folder.
  ///
  /// `connections.folder_id` is `ON DELETE CASCADE`, which would delete them
  /// with it. They are detached first, so the cascade finds nothing: no schema
  /// migration of the connections table is needed.
  Future<void> removeFolder(String name) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE connections SET folder_id = NULL WHERE folder_id IN '
        '(SELECT id FROM folders WHERE name = ?)',
        [name],
      );
      await txn.delete('folders', where: 'name = ?', whereArgs: [name]);
    });
  }

  /// Moves a connection into the folder [folderId], or out of any folder when
  /// it is null. Only the folder changes: secrets and settings are untouched.
  Future<void> setConnectionFolder(int connectionId, int? folderId) async {
    final db = await _open();
    await db.update(
      'connections',
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [connectionId],
    );
  }

  Future<void> clearFolders() async {
    final db = await _open();
    await db.delete('folders');
  }

  /// Makes the stored folders exactly [names], in one transaction: a failure
  /// leaves the old list. Folders that stay keep their connections; the ones
  /// that go release theirs first (see [removeFolder]).
  Future<void> replaceFolders(List<String> names) async {
    final wanted = <String>{
      for (final name in names)
        if (name.trim().isNotEmpty) name.trim(),
    };
    final db = await _open();
    await db.transaction((txn) async {
      final rows = await txn.query('folders', columns: ['name']);
      final existing = {for (final r in rows) r['name'] as String};
      for (final name in existing.difference(wanted)) {
        await txn.rawUpdate(
          'UPDATE connections SET folder_id = NULL WHERE folder_id IN '
          '(SELECT id FROM folders WHERE name = ?)',
          [name],
        );
        await txn.delete('folders', where: 'name = ?', whereArgs: [name]);
      }
      for (final name in wanted.difference(existing)) {
        await txn.insert('folders', {'name': name});
      }
    });
  }

  Future<int?> getFolderIdByName(String name) async {
    final db = await _open();
    final rows = await db.query('folders',
        columns: ['id'], where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return sqliteInt(rows.first['id']);
  }
}
