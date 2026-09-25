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

final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');
final _windowsDriveLetter = RegExp(r'(?:^|[/\\])[a-zA-Z]:');
final _windowsReservedDevice = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
  caseSensitive: false,
);

/// Rejects archive entry names that attempt absolute paths, directory traversal,
/// Windows drive letters, Windows reserved device names, or control characters.
bool isArchiveEntryNameSafe(String entryName) {
  if (entryName.isEmpty) return false;
  if (_controlCharacters.hasMatch(entryName)) return false;
  if (entryName.contains('..')) return false;
  if (entryName.startsWith('/') || entryName.startsWith('\\')) return false;
  if (_windowsDriveLetter.hasMatch(entryName)) return false;

  final segments = entryName.split(RegExp(r'[/\\]'));
  for (final segment in segments) {
    final trimmed = segment.trimRight();
    if (_windowsReservedDevice.hasMatch(trimmed)) return false;
  }

  return true;
}
