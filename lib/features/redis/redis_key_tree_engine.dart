import 'package:querya_desktop/core/database/redis_bulk.dart';

/// Information about a single Redis key.
class RedisKeyInfo {
  const RedisKeyInfo({
    required this.name,
    required this.type,
    required this.ttl,
  });

  final RedisBulkValue name;
  final String type;

  /// -1 = no expiry, -2 = key does not exist, >= 0 = seconds remaining
  final int ttl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RedisKeyInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          type == other.type &&
          ttl == other.ttl;

  @override
  int get hashCode => Object.hash(name, type, ttl);
}

/// Represents a virtual folder containing nested folders and leaf keys.
class RedisKeyFolderNode {
  RedisKeyFolderNode({
    required this.name,
    required this.fullPrefix,
    List<RedisKeyFolderNode>? folders,
    List<RedisKeyLeafNode>? leaves,
  })  : folders = folders ?? [],
        leaves = leaves ?? [];

  /// The segment name of this folder (e.g. 'user', '100').
  final String name;

  /// Full path prefix including the delimiter (e.g. 'user:', 'user:100:').
  final String fullPrefix;

  /// Subfolders nested under this folder.
  final List<RedisKeyFolderNode> folders;

  /// Key leaves directly inside this folder.
  final List<RedisKeyLeafNode> leaves;

  /// Total count of keys in this subtree (both direct leaves and nested leaves).
  int get totalKeyCount {
    var count = leaves.length;
    for (final f in folders) {
      count += f.totalKeyCount;
    }
    return count;
  }

  /// All leaf keys in this folder and its subfolders.
  List<RedisKeyInfo> get allKeys {
    final result = <RedisKeyInfo>[];
    for (final l in leaves) {
      result.add(l.keyInfo);
    }
    for (final f in folders) {
      result.addAll(f.allKeys);
    }
    return result;
  }
}

/// Represents a single Redis key leaf in the tree.
class RedisKeyLeafNode {
  const RedisKeyLeafNode({
    required this.name,
    required this.keyInfo,
  });

  /// The segment name of the key (e.g. 'profile' or the full key name if at root).
  final String name;

  /// The underlying Redis key information.
  final RedisKeyInfo keyInfo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RedisKeyLeafNode &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          keyInfo == other.keyInfo;

  @override
  int get hashCode => Object.hash(name, keyInfo);
}

/// The hierarchical tree representation of Redis keys grouped by delimiter.
class RedisKeyTree {
  const RedisKeyTree({
    required this.rootFolders,
    required this.rootLeaves,
    required this.delimiter,
  });

  final List<RedisKeyFolderNode> rootFolders;
  final List<RedisKeyLeafNode> rootLeaves;
  final String delimiter;

  bool get isEmpty => rootFolders.isEmpty && rootLeaves.isEmpty;

  int get totalKeyCount {
    var count = rootLeaves.length;
    for (final f in rootFolders) {
      count += f.totalKeyCount;
    }
    return count;
  }
}

class _MutableFolder {
  _MutableFolder({required this.name, required this.fullPrefix});

  final String name;
  final String fullPrefix;
  final Map<String, _MutableFolder> subfolders = {};
  final List<RedisKeyLeafNode> leaves = [];
}

/// Engine to partition and build a folder hierarchy of Redis keys by a delimiter.
class RedisKeyTreeEngine {
  const RedisKeyTreeEngine._();

  /// Builds a [RedisKeyTree] by grouping [keys] by [delimiter].
  ///
  /// If [delimiter] is empty or whitespace, all keys are placed at the root.
  static RedisKeyTree buildTree({
    required Iterable<RedisKeyInfo> keys,
    String delimiter = ':',
  }) {
    if (delimiter.isEmpty) {
      final leaves = [
        for (final k in keys) RedisKeyLeafNode(name: k.name.label, keyInfo: k),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return RedisKeyTree(
        rootFolders: const [],
        rootLeaves: leaves,
        delimiter: delimiter,
      );
    }

    final rootFolderMap = <String, _MutableFolder>{};
    final rootLeaves = <RedisKeyLeafNode>[];

    for (final key in keys) {
      final label = key.name.label;
      if (!label.contains(delimiter)) {
        rootLeaves.add(RedisKeyLeafNode(name: label, keyInfo: key));
        continue;
      }

      final parts = label.split(delimiter);
      // Example: 'user:100:profile' with ':' -> parts: ['user', '100', 'profile']
      // Folder segments: ['user', '100']
      // Leaf segment: 'profile'
      final folderSegments = parts.sublist(0, parts.length - 1);
      final rawLeaf = parts.last;
      final leafSegment = rawLeaf.isEmpty ? '(empty)' : rawLeaf;

      var currentMap = rootFolderMap;
      _MutableFolder? currentFolder;
      var currentPrefix = '';

      for (final seg in folderSegments) {
        currentPrefix = '$currentPrefix$seg$delimiter';
        currentFolder = currentMap.putIfAbsent(
          seg,
          () => _MutableFolder(name: seg, fullPrefix: currentPrefix),
        );
        currentMap = currentFolder.subfolders;
      }

      currentFolder!.leaves.add(
        RedisKeyLeafNode(name: leafSegment, keyInfo: key),
      );
    }

    rootLeaves.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    List<RedisKeyFolderNode> convertFolders(Map<String, _MutableFolder> map) {
      final sortedKeys = map.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final result = <RedisKeyFolderNode>[];
      for (final key in sortedKeys) {
        final mf = map[key]!;
        mf.leaves.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        result.add(
          RedisKeyFolderNode(
            name: mf.name,
            fullPrefix: mf.fullPrefix,
            folders: convertFolders(mf.subfolders),
            leaves: mf.leaves,
          ),
        );
      }
      return result;
    }

    final rootFolders = convertFolders(rootFolderMap);
    return RedisKeyTree(
      rootFolders: rootFolders,
      rootLeaves: rootLeaves,
      delimiter: delimiter,
    );
  }
}
