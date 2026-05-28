// Deep-merge VS Code `colors` maps (later layers override earlier keys).

/// Merges VS Code color layers left-to-right; returns an unmodifiable map.
///
/// Typical pipeline: `defaultColors` → `importedColors` → `userOverrides`.
Map<String, String> mergeVsCodeColorLayers(
  Iterable<Map<String, String>> layers,
) {
  final merged = <String, String>{};
  for (final layer in layers) {
    merged.addAll(layer);
  }
  return Map.unmodifiable(merged);
}
