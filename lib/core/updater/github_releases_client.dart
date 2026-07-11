import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_manifest.dart';
import 'update_version.dart';

const String kGitHubReleasesLatestUrl =
    'https://api.github.com/repos/QueryaHub/Querya-Desktop/releases/latest';

const String kGitHubReleasesListUrl =
    'https://api.github.com/repos/QueryaHub/Querya-Desktop/releases';

const String kSha256SumsFileName = 'SHA256SUMS.txt';

/// Fetches and parses GitHub Releases JSON for update checks.
class GitHubReleasesClient {
  GitHubReleasesClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<UpdateManifest> fetchLatest({required UpdateChannel channel}) async {
    if (channel == UpdateChannel.stable) {
      final response = await _httpClient.get(Uri.parse(kGitHubReleasesLatestUrl));
      if (response.statusCode != 200) {
        throw GitHubReleasesException(
          'GitHub Releases API returned HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GitHubReleasesException('Unexpected GitHub Releases payload');
      }
      return parseGitHubRelease(decoded);
    }

    final response = await _httpClient.get(Uri.parse(kGitHubReleasesListUrl));
    if (response.statusCode != 200) {
      throw GitHubReleasesException(
        'GitHub Releases API returned HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const GitHubReleasesException('Unexpected GitHub Releases list payload');
    }

    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] == true) continue;
      return parseGitHubRelease(entry);
    }

    throw const GitHubReleasesException('No published releases found');
  }

  Future<String> downloadText(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw GitHubReleasesException(
        'Failed to download $url (HTTP ${response.statusCode})',
      );
    }
    return response.body;
  }

  void close() => _httpClient.close();
}

/// Parses a single GitHub release object into [UpdateManifest].
UpdateManifest parseGitHubRelease(Map<String, dynamic> json) {
  final tagName = json['tag_name']?.toString();
  if (tagName == null || tagName.isEmpty) {
    throw const GitHubReleasesException('Release is missing tag_name');
  }

  final version = UpdateVersion.normalizeTag(tagName);
  final publishedAtRaw = json['published_at']?.toString();
  DateTime? releaseDate;
  if (publishedAtRaw != null && publishedAtRaw.isNotEmpty) {
    releaseDate = DateTime.tryParse(publishedAtRaw);
  }

  final body = json['body']?.toString() ?? '';
  final rawAssets = json['assets'];
  final assets = <UpdateAsset>[];
  String? checksumsUrl;

  if (rawAssets is List) {
    for (final raw in rawAssets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name']?.toString();
      final url = raw['browser_download_url']?.toString();
      if (name == null || name.isEmpty || url == null || url.isEmpty) {
        continue;
      }
      final size = raw['size'];
      final sizeBytes = size is int ? size : int.tryParse('$size');
      if (name == kSha256SumsFileName) {
        checksumsUrl = url;
      }
      assets.add(
        UpdateAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: sizeBytes,
        ),
      );
    }
  }

  return UpdateManifest(
    version: version,
    releaseDate: releaseDate,
    changelog: body,
    assets: assets,
    checksumsUrl: checksumsUrl,
  );
}

class GitHubReleasesException implements Exception {
  const GitHubReleasesException(this.message);

  final String message;

  @override
  String toString() => 'GitHubReleasesException: $message';
}
