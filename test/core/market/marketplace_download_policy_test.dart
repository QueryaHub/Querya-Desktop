import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/market/marketplace_download_policy.dart';

void main() {
  group('MarketplaceDownloadPolicy', () {
    test('trustedHostsFor includes API host and extras', () {
      expect(
        MarketplaceDownloadPolicy.trustedHostsFor(
          apiBaseUrl: 'https://api.example.com/api/v1',
          extraTrustedHosts: ['cdn.example.com'],
        ),
        {'api.example.com', 'cdn.example.com'},
      );
    });

    test('isAllowedApiBaseUrl allows public https API', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedApiBaseUrl(
          'https://api.example.com/api/v1',
          allowLocalhostInDebug: false,
        ),
        isTrue,
      );
    });

    test('isAllowedApiBaseUrl rejects cleartext in release mode', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedApiBaseUrl(
          'http://localhost:8000/api/v1',
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
    });

    test('isAllowedApiBaseUrl allows localhost http in debug mode', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedApiBaseUrl(
          'http://localhost:8000/api/v1',
          allowLocalhostInDebug: true,
        ),
        isTrue,
      );
    });

    test('isAllowedDownloadUrl rejects untrusted host', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedDownloadUrl(
          Uri.parse('https://evil.example.com/pkg.zip'),
          trustedHosts: {'api.example.com'},
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
    });

    test('isAllowedDownloadUrl rejects private IPs in release mode', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedDownloadUrl(
          Uri.parse('https://192.168.1.10/pkg.zip'),
          trustedHosts: {'192.168.1.10'},
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
    });

    test('isAllowedDownloadUrl rejects file scheme', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedDownloadUrl(
          Uri.parse('file:///etc/passwd'),
          trustedHosts: {'localhost'},
          allowLocalhostInDebug: true,
        ),
        isFalse,
      );
    });

    test('isAllowedDownloadUrl allows trusted public https host', () {
      expect(
        MarketplaceDownloadPolicy.isAllowedDownloadUrl(
          Uri.parse('https://cdn.example.com/pkg.zip'),
          trustedHosts: {'cdn.example.com'},
          allowLocalhostInDebug: false,
        ),
        isTrue,
      );
    });
  });
}
