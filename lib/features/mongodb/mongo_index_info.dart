/// Data model for a MongoDB collection index with metadata and size metrics.
class MongoIndexInfo {
  const MongoIndexInfo({
    required this.name,
    required this.keys,
    this.sizeBytes,
    this.isUnique = false,
    this.isSparse = false,
    this.expireAfterSeconds,
    this.version,
  });

  final String name;
  final Map<String, dynamic> keys;
  final int? sizeBytes;
  final bool isUnique;
  final bool isSparse;
  final int? expireAfterSeconds;
  final int? version;

  /// Whether this is the built-in primary index `_id_`, which cannot be deleted.
  bool get isPrimary =>
      name == '_id_' || (keys.length == 1 && keys.containsKey('_id'));

  /// Whether this index expires documents after a specified time.
  bool get isTtl => expireAfterSeconds != null;

  /// Categorized display label for the index type.
  String get indexType {
    if (isPrimary) return 'Primary';
    if (isTtl) return 'TTL';
    if (keys.values.any((v) => v.toString().toLowerCase() == 'text')) {
      return 'Text';
    }
    if (keys.values.any((v) =>
        v.toString().toLowerCase() == '2dsphere' ||
        v.toString().toLowerCase() == '2d')) {
      return 'Geospatial';
    }
    if (keys.length > 1) return 'Compound';
    return 'Single Field';
  }

  /// Formatted string of keys, e.g. `status: 1, createdAt: -1`.
  String get keysFormatted =>
      keys.entries.map((e) => '${e.key}: ${e.value}').join(', ');

  /// Human-readable representation of index size on disk.
  String get sizeFormatted {
    if (sizeBytes == null) return '—';
    final bytes = sizeBytes!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  factory MongoIndexInfo.fromMap(Map<String, dynamic> map) {
    final rawKey = map['key'];
    final keys = <String, dynamic>{};
    if (rawKey is Map) {
      for (final entry in rawKey.entries) {
        keys[entry.key.toString()] = entry.value;
      }
    }

    final rawSize = map['size'];
    int? sizeBytes;
    if (rawSize is num) {
      sizeBytes = rawSize.toInt();
    }

    return MongoIndexInfo(
      name: map['name']?.toString() ?? 'unnamed_index',
      keys: keys,
      sizeBytes: sizeBytes,
      isUnique: map['unique'] == true,
      isSparse: map['sparse'] == true,
      expireAfterSeconds: (map['expireAfterSeconds'] as num?)?.toInt(),
      version: (map['v'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MongoIndexInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          sizeBytes == other.sizeBytes &&
          isUnique == other.isUnique &&
          isSparse == other.isSparse &&
          expireAfterSeconds == other.expireAfterSeconds &&
          version == other.version;

  @override
  int get hashCode => Object.hash(
        name,
        sizeBytes,
        isUnique,
        isSparse,
        expireAfterSeconds,
        version,
      );
}
