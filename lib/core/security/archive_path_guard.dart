import 'package:path/path.dart' as p;

/// Returns true when [targetPath] equals [rootPath] or lies inside it.
///
/// Prefer over [String.startsWith] so sibling prefixes (e.g. `/tmp/abc` vs
/// `/tmp/abcd`) cannot bypass extraction bounds.
bool isArchiveExtractPathWithinRoot(String rootPath, String targetPath) {
  final root = p.normalize(rootPath);
  final target = p.normalize(targetPath);
  return p.equals(root, target) || p.isWithin(root, target);
}

/// Rejects archive entry names that attempt absolute paths or traversal.
bool isArchiveEntryNameSafe(String entryName) {
  if (entryName.contains('..')) return false;
  if (entryName.startsWith('/') || entryName.startsWith('\\')) return false;
  return true;
}
