import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/security/archive_path_guard.dart';
import 'marketplace_repository.dart';

/// HTTP implementation of [MarketplaceRepository] connecting to MarketApi backend.
///
/// Implements secure downloading with SHA256 checksum verification and safe
/// archive extraction preventing Path Traversal and Zip Bomb vulnerabilities (Issue #242).
class HttpMarketplaceRepository implements MarketplaceRepository {
  HttpMarketplaceRepository({
    this.baseUrl = 'http://localhost:8000/api/v1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<List<ExtensionManifest>> getTrending({ExtensionType? type}) async {
    final uri = Uri.parse('$baseUrl/extensions/trending').replace(
      queryParameters: type != null ? {'type': type.value} : null,
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw MarketplaceException('Failed to load trending extensions (HTTP ${response.statusCode})');
    }
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((json) => ExtensionManifest.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ExtensionManifest>> search(String query, {ExtensionType? type}) async {
    final uri = Uri.parse('$baseUrl/extensions/search').replace(
      queryParameters: {
        'q': query.trim(),
        if (type != null) 'type': type.value,
      },
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw MarketplaceException('Search failed (HTTP ${response.statusCode})');
    }
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((json) => ExtensionManifest.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<File> download(String url, {void Function(double)? onProgress}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw MarketplaceException('Invalid download URL: $url');
    }

    final request = http.Request('GET', uri);
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw MarketplaceException('Download failed with HTTP status ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    int received = 0;

    final tmpDir = Directory.systemTemp;
    final file = File(p.join(tmpDir.path, 'querya_ext_${DateTime.now().millisecondsSinceEpoch}.zip'));
    final sink = file.openWrite();

    try {
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      });
    } finally {
      await sink.close();
    }

    if (onProgress != null && contentLength == 0) {
      onProgress(1.0);
    }

    return file;
  }

  @override
  Future<void> install(
    ExtensionManifest manifest, {
    void Function(double)? onProgress,
  }) async {
    if (ExtensionSupport.isPreviewOnlyManifest(manifest)) {
      throw MarketplaceException(ExtensionSupport.databaseDriverPreviewNotice);
    }

    final sandboxViolations = SandboxPolicy.validate(manifest);
    if (sandboxViolations.isNotEmpty) {
      throw MarketplaceException(
        'Extension "${manifest.id}" requests sandbox permissions beyond the '
        'security policy: ${sandboxViolations.join(' ')}',
      );
    }

    final downloadUrl = manifest.downloadUrl;
    if (downloadUrl == null || downloadUrl.trim().isEmpty) {
      throw MarketplaceException('Extension manifest is missing downloadUrl');
    }

    // Step 1: Download archive with progress reporting (up to 80% of total progress)
    final archiveFile = await download(
      downloadUrl,
      onProgress: (p) => onProgress?.call(p * 0.8),
    );

    try {
      // Step 2: SHA-256 Integrity Verification (Critical Security Check)
      final expectedSha256 = manifest.sha256Checksum?.trim().toLowerCase();
      if (expectedSha256 == null || expectedSha256.isEmpty) {
        throw MarketplaceException(
          'Extension manifest is missing SHA256 checksum for "${manifest.id}". '
          'Installation aborted.',
        );
      }

      final bytes = await archiveFile.readAsBytes();
      final actualSha256 = sha256.convert(bytes).toString().toLowerCase();
      if (actualSha256 != expectedSha256) {
        throw MarketplaceException(
          'SHA256 checksum mismatch for "${manifest.id}". '
          'Expected: $expectedSha256, Actual: $actualSha256. Installation aborted.',
        );
      }

      onProgress?.call(0.85);

      // Step 3: Safe Archive Extraction (Preventing Path Traversal / Zip Bomb - Issue #242)
      final archive = ZipDecoder().decodeBytes(bytes);

      final dir = await ExtensionPaths.extensionsDirectory();
      final extDir = Directory(p.join(dir.path, manifest.id));
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      final extDirPath = p.normalize(extDir.path);

      for (final file in archive) {
        final filename = file.name;
        // Check for Path Traversal attempts
        if (!isArchiveEntryNameSafe(filename)) {
          throw MarketplaceException('Security violation: Path traversal detected in archive entry "$filename"');
        }

        final targetPath = p.normalize(p.join(extDirPath, filename));
        if (!isArchiveExtractPathWithinRoot(extDirPath, targetPath)) {
          throw MarketplaceException('Security violation: Extraction path out of bounds "$filename"');
        }

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }

      onProgress?.call(0.95);

      ExtensionSupport.validateDriverPackage(
        manifest: manifest,
        installDir: extDir,
      );
      await ExtensionSupport.ensureDriverExecutables(
        manifest: manifest,
        installDir: extDir,
      );

      // Step 4: Write/Update manifest.json in the extension directory
      final manifestFile = File(p.join(extDir.path, 'manifest.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString(encoder.convert(manifest.toJson()));

      // Step 5: Reload local extension registry
      await LocalExtensionRegistry.instance.reload();
      onProgress?.call(1.0);
    } finally {
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }
    }
  }

  @override
  Future<void> uninstall(String extensionId) async {
    final manifest = LocalExtensionRegistry.instance.manifests
        .where((e) => e.id == extensionId)
        .firstOrNull;

    if (manifest != null && manifest.installPath != null) {
      final extDir = Directory(manifest.installPath!);
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }
    } else {
      final dir = await ExtensionPaths.extensionsDirectory();
      final extDir = Directory(p.join(dir.path, extensionId));
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }
    }

    await LocalExtensionRegistry.instance.reload();
  }
}
