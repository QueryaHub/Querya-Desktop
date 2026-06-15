import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/theme_remote_install_policy.dart';

void main() {
  group('ThemeRemoteInstallPolicy', () {
    test('allows public https URLs', () {
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          Uri.parse('https://cdn.example.com/themes/neon.json'),
          allowLocalhostInDebug: false,
        ),
        isTrue,
      );
    });

    test('rejects http URLs', () {
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          Uri.parse('http://example.com/theme.json'),
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
    });

    test('rejects localhost unless debug override', () {
      final localhost = Uri.parse('https://localhost/theme.json');
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          localhost,
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          localhost,
          allowLocalhostInDebug: true,
        ),
        isTrue,
      );
    });

    test('rejects private IPv4 addresses', () {
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          Uri.parse('https://192.168.1.10/theme.json'),
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
      expect(
        ThemeRemoteInstallPolicy.isAllowedUrl(
          Uri.parse('https://10.0.0.5/theme.json'),
          allowLocalhostInDebug: false,
        ),
        isFalse,
      );
    });
  });
}
