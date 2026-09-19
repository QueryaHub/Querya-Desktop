/// Result of picking which live extension session should run a palette command.
enum ExtensionCommandTargetKind { none, ready, ambiguous }

class ExtensionCommandTarget {
  const ExtensionCommandTarget._(this.kind, this.connectionId);

  const ExtensionCommandTarget.none()
      : this._(ExtensionCommandTargetKind.none, null);

  const ExtensionCommandTarget.ready(int connectionId)
      : this._(ExtensionCommandTargetKind.ready, connectionId);

  const ExtensionCommandTarget.ambiguous()
      : this._(ExtensionCommandTargetKind.ambiguous, null);

  final ExtensionCommandTargetKind kind;
  final int? connectionId;

  bool get isReady => kind == ExtensionCommandTargetKind.ready;
}

/// Whether an extension may publish this command id into the palette.
///
/// Built-ins use `querya.*`. Contributions must use the `ext.` prefix so they
/// cannot clobber Execute / theme / etc.
bool isAllowedExtensionCommandId(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('querya.')) return false;
  return trimmed.startsWith('ext.');
}

/// Picks a live connection for [extensionId].
///
/// Prefers [preferredConnectionId] when that session is live for the same
/// package. A single live session is used even if nothing is selected.
/// Several live sessions without a matching selection are [ambiguous].
ExtensionCommandTarget resolveExtensionCommandTarget({
  required String extensionId,
  required Iterable<int> liveConnectionIds,
  required String? Function(int connectionId) extensionIdFor,
  int? preferredConnectionId,
}) {
  final live = [
    for (final id in liveConnectionIds)
      if (extensionIdFor(id) == extensionId) id,
  ];
  if (live.isEmpty) return const ExtensionCommandTarget.none();
  if (preferredConnectionId != null &&
      live.contains(preferredConnectionId)) {
    return ExtensionCommandTarget.ready(preferredConnectionId);
  }
  if (live.length == 1) {
    return ExtensionCommandTarget.ready(live.single);
  }
  return const ExtensionCommandTarget.ambiguous();
}
