import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:querya_desktop/core/extensions/harness/extension_manifest_validator.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

import 'marketplace_repository.dart';

/// The marketplace as a static file: `index.json` published by the extension
/// registry (`QueryaHub/extensions`, on GitHub Pages) with no server of ours.
///
/// The index is built by the registry's CI from the extensions' own release
/// archives, so every entry already carries the archive's SHA-256. Installing
/// is the safe pipeline of [HttpMarketplaceRepository] (checksum, archive
/// limits, sandbox policy); this class only adds where the list comes from and
/// that an archive may only come from a GitHub release.
class StaticRegistryRepository extends HttpMarketplaceRepository {
  StaticRegistryRepository({
    this.indexUrl = defaultIndexUrl,
    required this.hostVersion,
    super.client,
    super.allowLocalhostInDebug,
    this.cacheTtl = const Duration(minutes: 10),
    DateTime Function()? now,
  })  : _http = client ?? http.Client(),
        _now = now ?? DateTime.now,
        super(
          baseUrl: indexUrl,
          extraTrustedDownloadHosts: _releaseHosts,
        );

  static const defaultIndexUrl =
      'https://queryahub.github.io/extensions/index.json';

  /// The index format this client reads. A newer registry is refused rather
  /// than half understood.
  static const supportedSchema = 1;

  /// Where a release asset is served from: the redirect of
  /// `github.com/<owner>/<repo>/releases/download/...` ends on one of these.
  static const _releaseHosts = [
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  ];

  /// Querya Desktop version, to hide extensions whose `engines.querya_desktop`
  /// range does not include it.
  final String hostVersion;
  final String indexUrl;
  final Duration cacheTtl;
  final http.Client _http;
  final DateTime Function() _now;

  List<ExtensionManifest>? _cache;
  DateTime? _cachedAt;

  static final _releasePath = RegExp(r'^/[^/]+/[^/]+/releases/download/[^/]+/[^/]+$');

  /// `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>` only.
  static bool isReleaseAssetUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'github.com' &&
      _releasePath.hasMatch(uri.path);

  /// The installable, compatible extensions of the index (cached for
  /// [cacheTtl]; a failed refresh keeps serving the last good copy).
  Future<List<ExtensionManifest>> _entries() async {
    final cached = _cache;
    final at = _cachedAt;
    if (cached != null && at != null && _now().difference(at) < cacheTtl) {
      return cached;
    }
    try {
      final response = await _http
          .get(Uri.parse(indexUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw MarketplaceException(
            'Could not load the registry (HTTP ${response.statusCode})');
      }
      final body = response.body;
      final decoded = await Isolate.run(() => jsonDecode(body));
      _cache = parseIndex(decoded, hostVersion: hostVersion);
      _cachedAt = _now();
      return _cache!;
    } catch (e) {
      if (cached != null) {
        debugPrint('Registry refresh failed, using the last copy: $e');
        return cached;
      }
      if (e is MarketplaceException) rethrow;
      throw MarketplaceException('Could not load the registry: $e');
    }
  }

  /// Entries of a decoded `index.json` that can be shown: not yanked, with a
  /// release-asset URL and a checksum, and compatible with [hostVersion].
  @visibleForTesting
  static List<ExtensionManifest> parseIndex(
    Object? decoded, {
    required String hostVersion,
  }) {
    if (decoded is! Map) {
      throw MarketplaceException('The registry index is not a JSON object');
    }
    final schema = decoded['schema'];
    if (schema != supportedSchema) {
      throw MarketplaceException(
          'The registry uses index format $schema; this Querya reads '
          '$supportedSchema. Update Querya Desktop.');
    }
    final host = HostVersion.parse(hostVersion);
    final out = <ExtensionManifest>[];
    for (final raw in (decoded['extensions'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      if (json['yanked'] == true) continue;
      try {
        final manifest = ExtensionManifest.fromJson(json);
        final url = Uri.tryParse(manifest.downloadUrl ?? '');
        if (url == null || !isReleaseAssetUrl(url)) continue;
        if ((manifest.sha256Checksum ?? '').trim().isEmpty) continue;
        final range = manifest.engines['querya_desktop'];
        if (range != null && engineRangeAllows(host, range) == false) continue;
        out.add(manifest);
      } catch (_) {
        // One malformed entry must not hide the rest of the registry.
      }
    }
    return out;
  }

  @override
  Future<List<ExtensionManifest>> getTrending({ExtensionType? type}) async {
    final all = await _entries();
    return [
      for (final m in all)
        if (type == null || m.type == type) m,
    ];
  }

  @override
  Future<List<ExtensionManifest>> search(String query,
      {ExtensionType? type}) async {
    final q = query.trim().toLowerCase();
    final all = await getTrending(type: type);
    if (q.isEmpty) return all;
    return [
      for (final m in all)
        if (m.name.toLowerCase().contains(q) ||
            m.id.toLowerCase().contains(q) ||
            m.publisher.toLowerCase().contains(q) ||
            (m.description?.toLowerCase().contains(q) ?? false) ||
            m.tags.any((t) => t.toLowerCase().contains(q)))
          m,
    ];
  }

  @override
  Future<File> download(String url, {void Function(double)? onProgress}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !isReleaseAssetUrl(uri)) {
      throw MarketplaceException(
          'Only a GitHub release asset may be downloaded from the registry: $url');
    }
    return super.download(url, onProgress: onProgress);
  }
}
