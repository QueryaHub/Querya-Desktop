/// Feature flags reported by an extension database driver via `db.getCapabilities`.
class ExtensionDriverCapabilities {
  const ExtensionDriverCapabilities({
    this.supportsTransactions = false,
    this.supportsCancel = false,
    this.supportsDDLInspection = false,
    this.supportsPrivileges = false,
    this.hasServerStats = false,
    this.supportsMutations = false,
    this.supportsBatchMutations = false,
  });

  /// True if `db.query` supports transaction control queries (BEGIN, COMMIT, ROLLBACK).
  final bool supportsTransactions;

  /// True if the driver supports `db.cancelQuery`.
  final bool supportsCancel;

  /// True if the driver supports `db.getObjectDDL` / `db.getObjectMetadata`.
  final bool supportsDDLInspection;

  /// True if the driver supports privilege inspection/grant management.
  final bool supportsPrivileges;

  /// True if the driver supports `db.getServerStats`.
  final bool hasServerStats;

  /// True if the driver supports `db.getTableSchema` and `db.mutate`.
  final bool supportsMutations;

  /// True if the driver supports batch multi-row mutations in `db.mutate`.
  final bool supportsBatchMutations;

  factory ExtensionDriverCapabilities.fromRpc(Object? raw) {
    if (raw is! Map) return const ExtensionDriverCapabilities();
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);
    return ExtensionDriverCapabilities(
      supportsTransactions:
          map['supportsTransactions'] == true ||
          map['supports_transactions'] == true,
      supportsCancel:
          map['supportsCancel'] == true || map['supports_cancel'] == true,
      supportsDDLInspection:
          map['supportsDDLInspection'] == true ||
          map['supports_ddl_inspection'] == true,
      supportsPrivileges:
          map['supportsPrivileges'] == true ||
          map['supports_privileges'] == true,
      hasServerStats:
          map['hasServerStats'] == true || map['has_server_stats'] == true,
      supportsMutations:
          map['supportsMutations'] == true || map['supports_mutations'] == true,
      supportsBatchMutations:
          map['supportsBatchMutations'] == true ||
          map['supports_batch_mutations'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'supportsTransactions': supportsTransactions,
        'supportsCancel': supportsCancel,
        'supportsDDLInspection': supportsDDLInspection,
        'supportsPrivileges': supportsPrivileges,
        'hasServerStats': hasServerStats,
        'supportsMutations': supportsMutations,
        'supportsBatchMutations': supportsBatchMutations,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionDriverCapabilities &&
          runtimeType == other.runtimeType &&
          supportsTransactions == other.supportsTransactions &&
          supportsCancel == other.supportsCancel &&
          supportsDDLInspection == other.supportsDDLInspection &&
          supportsPrivileges == other.supportsPrivileges &&
          hasServerStats == other.hasServerStats &&
          supportsMutations == other.supportsMutations &&
          supportsBatchMutations == other.supportsBatchMutations;

  @override
  int get hashCode =>
      Object.hash(
        supportsTransactions,
        supportsCancel,
        supportsDDLInspection,
        supportsPrivileges,
        hasServerStats,
        supportsMutations,
        supportsBatchMutations,
      );
}
