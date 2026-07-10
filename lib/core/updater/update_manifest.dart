/// Distribution channel for desktop update checks.
enum UpdateChannel {
  stable,
  dev,
}

/// A downloadable release artifact (platform zip, checksum file, etc.).
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeBytes,
    this.sha256,
  });

  final String name;
  final String downloadUrl;
  final int? sizeBytes;

  /// Expected SHA256 hex digest from [UpdateManifest.checksums], if known.
  final String? sha256;

  UpdateAsset copyWith({String? sha256}) {
    return UpdateAsset(
      name: name,
      downloadUrl: downloadUrl,
      sizeBytes: sizeBytes,
      sha256: sha256 ?? this.sha256,
    );
  }
}

/// Parsed release metadata from GitHub Releases (or a compatible proxy feed).
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.changelog,
    required this.assets,
    this.releaseDate,
    this.checksumsUrl,
    this.checksums = const {},
  });

  final String version;
  final DateTime? releaseDate;
  final String changelog;
  final List<UpdateAsset> assets;
  final String? checksumsUrl;

  /// File name → lowercase SHA256 hex digest.
  final Map<String, String> checksums;

  UpdateAsset? assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  UpdateManifest withChecksums(Map<String, String> checksums) {
    final enriched = assets
        .map(
          (asset) => checksums.containsKey(asset.name)
              ? asset.copyWith(sha256: checksums[asset.name])
              : asset,
        )
        .toList(growable: false);
    return UpdateManifest(
      version: version,
      releaseDate: releaseDate,
      changelog: changelog,
      assets: enriched,
      checksumsUrl: checksumsUrl,
      checksums: checksums,
    );
  }
}

/// Result of [AppUpdaterService.checkForUpdates].
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.availableUpdate,
    this.errorMessage,
  });

  final String currentVersion;
  final UpdateManifest? availableUpdate;
  final String? errorMessage;

  bool get hasUpdate => availableUpdate != null;
  bool get isUpToDate => availableUpdate == null && errorMessage == null;
}

typedef UpdateDownloadProgressCallback = void Function(int received, int total);
