import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_db.dart';

const _legacyFileName = 'folders.json';
const _keyFolders = 'folders';

/// Persists browser folder names using local SQLite ([LocalDb]).
/// On first load, migrates from legacy JSON if present.
class FoldersStorage {
  FoldersStorage._();
  static final FoldersStorage instance = FoldersStorage._();

  List<String> _folders = [];
  bool _loaded = false;
  bool _migrationChecked = false;

  List<String> get folders => List.unmodifiable(_folders);

  Future<List<String>> load() async {
    if (_loaded) return folders;
    try {
      await _migrateFromLegacyIfNeeded();
      _folders = await LocalDb.instance.getFolders();
    } catch (_) {
      _folders = [];
    }
    _loaded = true;
    return folders;
  }

  Future<void> _migrateFromLegacyIfNeeded() async {
    if (_migrationChecked) return;
    _migrationChecked = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final sub = Directory('${dir.path}/querya_desktop');
      final file = File('${sub.path}/$_legacyFileName');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, Object?>;
      final list = decoded[_keyFolders];
      final names = list != null && list is List<Object?>
          ? list.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
          : <String>[];
      final existing = await LocalDb.instance.getFolders();
      for (final name in names) {
        if (!existing.contains(name)) {
          await LocalDb.instance.addFolder(name);
        }
      }
      await file.delete();
    } catch (_) {}
  }

  Future<void> save(List<String> folders) async {
    _folders = List.from(folders);
    await LocalDb.instance.clearFolders();
    for (final name in _folders) {
      await LocalDb.instance.addFolder(name);
    }
  }

  Future<void> add(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await load();
    if (_folders.contains(n)) return;
    await LocalDb.instance.addFolder(n);
    _folders = await LocalDb.instance.getFolders();
  }

  Future<void> remove(String name) async {
    await load();
    await LocalDb.instance.removeFolder(name);
    _folders = await LocalDb.instance.getFolders();
  }

  /// Reloads folder names from [LocalDb] (e.g. after external seeding in tests).
  Future<void> reload() async {
    _loaded = false;
    await load();
  }
}
