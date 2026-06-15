import 'package:flutter/foundation.dart';

/// HTTPS trust rules for remote theme install (TP-F4).
abstract final class ThemeRemoteInstallPolicy {
  /// Returns true when [uri] may be used for theme download.
  static bool isAllowedUrl(Uri uri, {bool allowLocalhostInDebug = kDebugMode}) {
    if (uri.scheme != 'https') return false;
    if (!uri.hasAuthority || uri.host.isEmpty) return false;

    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '0.0.0.0') {
      return allowLocalhostInDebug;
    }
    if (host == '::1' || host.endsWith('.local')) {
      return allowLocalhostInDebug;
    }

    final ipv4 = _parseIpv4(host);
    if (ipv4 != null) {
      if (_isLoopbackIpv4(ipv4) || _isPrivateIpv4(ipv4) || _isLinkLocalIpv4(ipv4)) {
        return allowLocalhostInDebug;
      }
    }

    return true;
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final bytes = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      bytes.add(value);
    }
    return bytes;
  }

  static bool _isLoopbackIpv4(List<int> ip) => ip[0] == 127;

  static bool _isLinkLocalIpv4(List<int> ip) => ip[0] == 169 && ip[1] == 254;

  static bool _isPrivateIpv4(List<int> ip) {
    if (ip[0] == 10) return true;
    if (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) return true;
    if (ip[0] == 192 && ip[1] == 168) return true;
    return false;
  }
}
