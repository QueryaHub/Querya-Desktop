/// Lightweight SemVer parser for update comparison (major.minor.patch + optional pre-release).
class UpdateVersion implements Comparable<UpdateVersion> {
  const UpdateVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;

  /// Lowercase pre-release label after `-`, e.g. `beta.1`; `null` for stable.
  final String? preRelease;

  bool get isPreRelease => preRelease != null && preRelease!.isNotEmpty;

  /// Strips an optional leading `v` from Git tag names.
  static String normalizeTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  }

  static UpdateVersion? tryParse(String raw) {
    final normalized = normalizeTag(raw);
    if (normalized.isEmpty) return null;

    final dash = normalized.indexOf('-');
    final core = dash >= 0 ? normalized.substring(0, dash) : normalized;
    final pre = dash >= 0 ? normalized.substring(dash + 1) : null;

    final parts = core.split('.');
    if (parts.length < 3) return null;

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;

    return UpdateVersion(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: (pre == null || pre.isEmpty) ? null : pre.toLowerCase(),
    );
  }

  /// Whether [candidate] is strictly newer than [current] for the given channel.
  static bool isUpdateAvailable({
    required UpdateVersion current,
    required UpdateVersion candidate,
    required bool allowPreRelease,
  }) {
    if (candidate.compareTo(current) <= 0) return false;
    if (!allowPreRelease && candidate.isPreRelease) return false;
    return true;
  }

  @override
  int compareTo(UpdateVersion other) {
    final core = _compareCore(other);
    if (core != 0) return core;

    if (!isPreRelease && !other.isPreRelease) return 0;
    if (!isPreRelease && other.isPreRelease) return 1;
    if (isPreRelease && !other.isPreRelease) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  int _compareCore(UpdateVersion other) {
    final majorCmp = major.compareTo(other.major);
    if (majorCmp != 0) return majorCmp;
    final minorCmp = minor.compareTo(other.minor);
    if (minorCmp != 0) return minorCmp;
    return patch.compareTo(other.patch);
  }

  @override
  String toString() =>
      isPreRelease ? '$major.$minor.$patch-$preRelease' : '$major.$minor.$patch';
}
