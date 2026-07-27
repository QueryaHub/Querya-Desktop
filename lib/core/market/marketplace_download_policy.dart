import 'package:flutter/foundation.dart';

import '../theme/theme_remote_install_policy.dart';

/// HTTPS and host allowlist rules for marketplace API and artifact downloads.
abstract final class MarketplaceDownloadPolicy {
  /// Hosts permitted for extension archive downloads (API host + extras).
  static Set<String> trustedHostsFor({
    required String apiBaseUrl,
    Iterable<String> extraTrustedHosts = const [],
  }) {
    final hosts = <String>{};
    final apiHost = Uri.tryParse(apiBaseUrl.trim())?.host.toLowerCase();
    if (apiHost != null && apiHost.isNotEmpty) {
      hosts.add(apiHost);
    }
    for (final host in extraTrustedHosts) {
      final normalized = host.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        hosts.add(normalized);
      }
    }
    return hosts;
  }

  /// Whether [baseUrl] may be used for MarketApi REST calls.
  static bool isAllowedApiBaseUrl(
    String baseUrl, {
    bool allowLocalhostInDebug = kDebugMode,
  }) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return false;
    }

    if (uri.scheme == 'https') {
      return ThemeRemoteInstallPolicy.isAllowedUrl(
        uri,
        allowLocalhostInDebug: allowLocalhostInDebug,
      );
    }

    if (allowLocalhostInDebug && uri.scheme == 'http') {
      return _isDebugLocalHttpHost(uri.host);
    }

    return false;
  }

  /// Whether [uri] may be used to download an extension archive.
  static bool isAllowedDownloadUrl(
    Uri uri, {
    required Set<String> trustedHosts,
    bool allowLocalhostInDebug = kDebugMode,
  }) {
    if (!uri.hasAuthority || uri.host.isEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (!trustedHosts.contains(host)) {
      return false;
    }

    if (uri.scheme == 'https') {
      return ThemeRemoteInstallPolicy.isAllowedUrl(
        uri,
        allowLocalhostInDebug: allowLocalhostInDebug,
      );
    }

    if (allowLocalhostInDebug && uri.scheme == 'http') {
      return _isDebugLocalHttpHost(host);
    }

    return false;
  }

  static bool _isDebugLocalHttpHost(String host) {
    final probe = Uri.parse('https://$host/');
    return ThemeRemoteInstallPolicy.isAllowedUrl(
      probe,
      allowLocalhostInDebug: true,
    );
  }
}
