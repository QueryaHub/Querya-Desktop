import 'dart:io';
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

    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.isLoopback || ip.isLinkLocal) {
        return allowLocalhostInDebug;
      }

      if (ip.type == InternetAddressType.IPv4) {
        if (_isPrivateIpv4(ip.rawAddress)) {
          return allowLocalhostInDebug;
        }
      } else if (ip.type == InternetAddressType.IPv6) {
        final bytes = ip.rawAddress;

        // Check for Unique Local Address (fc00::/7) -> first byte is 0xfc or 0xfd
        final isUla = bytes[0] == 0xfc || bytes[0] == 0xfd;

        // Check for Multicast (ff00::/8) -> first byte is 0xff
        final isMulticast = bytes[0] == 0xff;

        // Check for Unspecified (::) -> all 16 bytes are 0
        final isUnspecified = bytes.every((b) => b == 0);

        if (isUla || isMulticast || isUnspecified) {
          return allowLocalhostInDebug;
        }

        // Check for IPv4-mapped IPv6 address (::ffff:x.x.x.x)
        if (_isIpv4Mapped(bytes)) {
          final ipv4Bytes = bytes.sublist(12, 16);
          if (ipv4Bytes[0] == 127 || // Loopback
              (ipv4Bytes[0] == 169 && ipv4Bytes[1] == 254) || // Link-local
              _isPrivateIpv4(ipv4Bytes)) {
            return allowLocalhostInDebug;
          }
        }
      }
    }

    return true;
  }

  static bool _isIpv4Mapped(List<int> bytes) {
    for (var i = 0; i < 10; i++) {
      if (bytes[i] != 0) return false;
    }
    return bytes[10] == 0xff && bytes[11] == 0xff;
  }

  static bool _isPrivateIpv4(List<int> ip) {
    if (ip[0] == 10) return true;
    if (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) return true;
    if (ip[0] == 192 && ip[1] == 168) return true;
    return false;
  }
}
