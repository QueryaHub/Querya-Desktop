import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'theme_import_service.dart';
import 'theme_registry_service.dart';
import 'theme_remote_install_policy.dart';

/// HTTP response shape used by [ThemeRemoteInstallService] (mockable in tests).
class RemoteThemeHttpResponse {
  const RemoteThemeHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

/// Downloads a theme from HTTPS and imports it via [ThemeRegistryService].
class ThemeRemoteInstallService {
  ThemeRemoteInstallService(
    this._registry, {
    Future<RemoteThemeHttpResponse> Function(Uri uri)? httpGet,
    Duration timeout = const Duration(seconds: 30),
    bool allowLocalhostInDebug = true,
  })  : _httpGet = httpGet ?? _defaultHttpGet,
        _timeout = timeout,
        _allowLocalhostInDebug = allowLocalhostInDebug;

  final ThemeRegistryService _registry;
  final Future<RemoteThemeHttpResponse> Function(Uri uri) _httpGet;
  final Duration _timeout;
  final bool _allowLocalhostInDebug;

  static Future<RemoteThemeHttpResponse> _defaultHttpGet(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    return RemoteThemeHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  /// Downloads [url] and imports into the user themes directory.
  ///
  /// [sha256Checksum] may be passed explicitly or via `?sha256=` on the URL.
  Future<ThemeDefinitionImportResult> installFromUrl(
    String url, {
    String? sha256Checksum,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const ThemeDefinitionImportFailure('Theme URL is required.');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return const ThemeDefinitionImportFailure('Invalid theme URL.');
    }

    if (!ThemeRemoteInstallPolicy.isAllowedUrl(
      uri,
      allowLocalhostInDebug: _allowLocalhostInDebug,
    )) {
      return const ThemeDefinitionImportFailure(
        'Only public HTTPS theme URLs are allowed.',
      );
    }

    final expectedChecksum = _normalizeSha256(
      sha256Checksum ?? uri.queryParameters['sha256'],
    );

    File? tempFile;
    try {
      final response = await _httpGet(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        return ThemeDefinitionImportFailure(
          'Download failed (HTTP ${response.statusCode}).',
        );
      }

      final body = response.body;
      if (body.trim().isEmpty) {
        return const ThemeDefinitionImportFailure('Downloaded theme file is empty.');
      }

      final actualChecksum = sha256.convert(utf8.encode(body)).toString();
      if (expectedChecksum != null && expectedChecksum != actualChecksum) {
        return const ThemeDefinitionImportFailure(
          'Checksum mismatch. Theme was not installed.',
        );
      }

      final tempDir = Directory.systemTemp.createTempSync('querya_theme_remote_');
      tempFile = File(p.join(tempDir.path, 'remote-theme.json'));
      await tempFile.writeAsString(body);

      return await _registry.importThemeFile(tempFile.path);
    } on TimeoutException {
      return const ThemeDefinitionImportFailure('Download timed out.');
    } on SocketException catch (error) {
      return ThemeDefinitionImportFailure('Network error: ${error.message}');
    } on HttpException catch (error) {
      return ThemeDefinitionImportFailure('Network error: ${error.message}');
    } on IOException catch (error) {
      return ThemeDefinitionImportFailure(error.toString());
    } on Object catch (error) {
      return ThemeDefinitionImportFailure(error.toString());
    } finally {
      if (tempFile != null) {
        try {
          final parent = tempFile.parent;
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          if (await parent.exists()) {
            await parent.delete(recursive: true);
          }
        } on Object {
          // Best-effort temp cleanup.
        }
      }
    }
  }

  static String? _normalizeSha256(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'[^0-9a-f]'), '');
  }
}
