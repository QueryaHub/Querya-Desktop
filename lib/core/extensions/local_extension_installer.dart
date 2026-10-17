import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/security/archive_path_guard.dart';
import 'package:querya_desktop/core/security/safe_zip_extractor.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';

/// Installs an extension package from a local `.zip` / `.qext` archive (issue #316).
///
/// Reuses the same security checks as marketplace install: path-traversal
/// rejection, SandboxPolicy, preview-only gate, and driver entry validation.
class LocalExtensionInstaller {
  LocalExtensionInstaller({
    Future<Directory> Function()? extensionsDirectory,
    Future<void> Function()? reloadRegistry,
    Future<void> Function(String extensionId)? stopSessionsForExtension,
  })  : _extensionsDirectory =
            extensionsDirectory ?? ExtensionPaths.ensureExtensionsDirectory,
        _reloadRegistry = reloadRegistry ?? _defaultReloadRegistry,
        _stopSessionsForExtension =
            stopSessionsForExtension ?? _defaultStopSessionsForExtension;

  static Future<void> _defaultReloadRegistry() =>
      LocalExtensionRegistry.instance.reload();

  static Future<void> _defaultStopSessionsForExtension(String extensionId) =>
      ExtensionDriverSession.instance.stopAllForExtension(extensionId);

  final Future<Directory> Function() _extensionsDirectory;
  final Future<void> Function() _reloadRegistry;
  final Future<void> Function(String extensionId) _stopSessionsForExtension;

  /// Reads [archiveFile], validates, extracts under `extensions/<id>/`, reloads.
  Future<ExtensionManifest> installFromArchive(
    File archiveFile, {
    String? expectedSha256,
    void Function(double progress)? onProgress,
  }) async {
    if (!await archiveFile.exists()) {
      throw MarketplaceException(
        'Extension archive not found: ${archiveFile.path}',
      );
    }

    onProgress?.call(0.1);
    try {
      await SafeZipExtractor.ensureCompressedSizeAllowed(archiveFile);
    } on SafeZipException catch (error) {
      throw MarketplaceException(error.message);
    }

    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final actual = (await sha256HexOfFile(archiveFile)).toLowerCase();
      final expected = expectedSha256.trim().toLowerCase();
      if (actual != expected) {
        throw MarketplaceException(
          'SHA256 checksum mismatch. Expected: $expected, Actual: $actual. '
          'Installation aborted.',
        );
      }
    }

    onProgress?.call(0.25);
    late final Archive archive;
    try {
      archive = await SafeZipExtractor.readAndDecodeFile(archiveFile);
    } on SafeZipException catch (error) {
      throw MarketplaceException(error.message);
    }
    if (archive.isEmpty) {
      throw MarketplaceException('Extension archive is empty.');
    }

    final stripPrefix = _commonRootPrefix(archive);
    final manifestEntry = _findManifestEntry(archive, stripPrefix);
    if (manifestEntry == null) {
      throw MarketplaceException(
        'Archive does not contain manifest.json.',
      );
    }

    late final ExtensionManifest manifest;
    try {
      final json = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
          as Map<String, dynamic>;
      manifest = ExtensionManifest.fromJson(json);
    } catch (e) {
      throw MarketplaceException('Invalid manifest.json: $e');
    }

    if (manifest.id.trim().isEmpty) {
      throw MarketplaceException('manifest.json is missing a valid "id".');
    }

    if (ExtensionSupport.isPreviewOnlyManifest(manifest)) {
      throw MarketplaceException(ExtensionSupport.databaseDriverPreviewNotice);
    }

    final formatProblem = ExtensionSupport.manifestFormatProblem(manifest);
    if (formatProblem != null) throw MarketplaceException(formatProblem);

    final sandboxViolations = SandboxPolicy.validate(manifest);
    if (sandboxViolations.isNotEmpty) {
      throw MarketplaceException(
        'Extension "${manifest.id}" requests sandbox permissions beyond the '
        'security policy: ${sandboxViolations.join(' ')}',
      );
    }

    onProgress?.call(0.4);

    final extDir = await installArchive(
      archive: archive,
      manifest: manifest,
      onProgress: onProgress,
    );
    return ExtensionManifest.fromJson(
      {
        ...manifest.toJson(),
        // installPath is not part of toJson; reload will set it.
      },
      installPath: extDir.path,
    );
  }

  /// Extracts [archive] into a hidden sibling of `extensions/<id>/`, validates
  /// it there and only then swaps it in, so a failed install or upgrade leaves
  /// the previous version untouched (#1562). Shared by local and marketplace
  /// installs; [manifest] is what gets written as `manifest.json`.
  Future<Directory> installArchive({
    required Archive archive,
    required ExtensionManifest manifest,
    void Function(double progress)? onProgress,
  }) async {
    // A running driver process for this extension holds its executable/DLL
    // open; on Windows that mandatory lock makes the swap below fail with
    // Access is denied (#891). Stop every live session first.
    await _stopSessionsForExtension(manifest.id);

    final root = await _extensionsDirectory();
    final extDir = ExtensionPaths.extensionDirectory(root, manifest.id);
    // Dot-prefixed: the registry skips them and an extension id cannot start
    // with a dot, so they never collide with or shadow a real install.
    final staging = Directory(p.join(root.path, '.${manifest.id}.installing'));
    final backup = Directory(p.join(root.path, '.${manifest.id}.backup'));

    var swapped = false;
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      // A backup left by a crashed swap is the last good install: put it back
      // rather than letting this attempt delete it.
      if (await backup.exists()) {
        if (await extDir.exists()) {
          await backup.delete(recursive: true);
        } else {
          await backup.rename(extDir.path);
        }
      }
      await staging.create(recursive: true);

      await _extractArchive(
        archive: archive,
        destDir: staging,
        stripPrefix: _commonRootPrefix(archive),
      );
      onProgress?.call(0.85);

      ExtensionSupport.validateDriverPackage(
        manifest: manifest,
        installDir: staging,
      );
      await ExtensionSupport.ensureDriverExecutables(
        manifest: manifest,
        installDir: staging,
      );

      // Ensure canonical manifest on disk (pretty-printed, with install metadata).
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString(
        encoder.convert(manifest.toJson()),
      );

      final hadPrevious = await extDir.exists();
      if (hadPrevious) await extDir.rename(backup.path);
      try {
        await staging.rename(extDir.path);
        swapped = true;
      } catch (_) {
        if (hadPrevious && !await extDir.exists()) {
          await backup.rename(extDir.path);
        }
        rethrow;
      }
      if (hadPrevious) {
        // The new version is in place; a leftover backup is only clutter.
        try {
          await backup.delete(recursive: true);
        } catch (_) {}
      }

      await _reloadRegistry();
      onProgress?.call(1.0);
      return extDir;
    } catch (e) {
      // The previous install was never touched; drop only the half-built one.
      try {
        if (!swapped && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } catch (_) {}
      if (e is MarketplaceException) rethrow;
      throw MarketplaceException('Failed to install extension: $e');
    }
  }

  /// Installs from a filesystem path (`.zip` / `.qext`).
  Future<ExtensionManifest> installFromPath(
    String path, {
    String? expectedSha256,
    void Function(double progress)? onProgress,
  }) {
    return installFromArchive(
      File(path),
      expectedSha256: expectedSha256,
      onProgress: onProgress,
    );
  }

  static ArchiveFile? _findManifestEntry(Archive archive, String stripPrefix) {
    ArchiveFile? best;
    var bestDepth = 1 << 30;
    for (final file in archive) {
      if (!file.isFile) continue;
      var name = file.name.replaceAll('\\', '/');
      if (stripPrefix.isNotEmpty && name.startsWith(stripPrefix)) {
        name = name.substring(stripPrefix.length);
      }
      if (name == 'manifest.json' || name.endsWith('/manifest.json')) {
        final depth = '/'.allMatches(name).length;
        if (depth < bestDepth) {
          bestDepth = depth;
          best = file;
        }
      }
    }
    return best;
  }

  /// If every entry shares a single top-level folder, return `"folder/"`.
  static String _commonRootPrefix(Archive archive) {
    String? root;
    for (final file in archive) {
      var name = file.name.replaceAll('\\', '/');
      if (name.isEmpty || name == '/') continue;
      // Skip macOS resource forks.
      if (name.startsWith('__MACOSX/')) continue;

      final parts = name.split('/');
      if (parts.length < 2) {
        return ''; // file at archive root → no strip
      }
      final candidate = '${parts.first}/';
      root ??= candidate;
      if (root != candidate) return '';
    }
    return root ?? '';
  }

  static Future<void> _extractArchive({
    required Archive archive,
    required Directory destDir,
    required String stripPrefix,
  }) async {
    final destPath = p.normalize(destDir.path);

    for (final file in archive) {
      var filename = file.name.replaceAll('\\', '/');
      if (filename.startsWith('__MACOSX/')) continue;
      // Judge the name as the archive wrote it: a shared `../` root would
      // otherwise be stripped away together with the prefix.
      if (!isArchiveEntryNameSafe(filename)) {
        throw MarketplaceException(
          'Security violation: Path traversal detected in archive entry '
          '"${file.name}"',
        );
      }
      if (stripPrefix.isNotEmpty && filename.startsWith(stripPrefix)) {
        filename = filename.substring(stripPrefix.length);
      }
      if (filename.isEmpty || filename == '/') continue;

      if (!isArchiveEntryNameSafe(filename)) {
        throw MarketplaceException(
          'Security violation: Path traversal detected in archive entry '
          '"${file.name}"',
        );
      }

      final targetPath = p.normalize(p.join(destPath, filename));
      if (!isArchiveExtractPathWithinRoot(destPath, targetPath)) {
        throw MarketplaceException(
          'Security violation: Extraction path out of bounds "${file.name}"',
        );
      }

      if (file.isFile) {
        final outFile = File(targetPath);
        await outFile.parent.create(recursive: true);
        final Uint8List bytes;
        try {
          bytes = SafeZipExtractor.readEntry(file);
        } on SafeZipException catch (error) {
          throw MarketplaceException(error.message);
        }
        await outFile.writeAsBytes(bytes);
        file.clear();
      } else {
        await Directory(targetPath).create(recursive: true);
      }
    }
  }
}
