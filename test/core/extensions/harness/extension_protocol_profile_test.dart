import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

void main() {
  group('HostVersion', () {
    test('parses plain, prefixed and build-suffixed versions', () {
      expect(HostVersion.parse('0.4.18'), const HostVersion(0, 4, 18));
      expect(HostVersion.parse('v0.5.0'), const HostVersion(0, 5, 0));
      expect(HostVersion.parse('0.4.19+2'), const HostVersion(0, 4, 19));
    });

    test('rejects malformed input', () {
      expect(() => HostVersion.parse('0.4'), throwsFormatException);
      expect(() => HostVersion.parse('latest'), throwsFormatException);
    });

    test('orders by major, minor, patch', () {
      expect(HostVersion.parse('0.4.9') < HostVersion.parse('0.4.10'), isTrue);
      expect(HostVersion.parse('0.5.0') >= HostVersion.parse('0.4.99'), isTrue);
    });
  });

  group('ExtensionProtocolProfile', () {
    test('0.4.11 has the core lifecycle but no table schema or commands', () {
      final p = ExtensionProtocolProfile.forTarget('0.4.11');
      expect(p.supports('system.handshake'), isTrue);
      expect(p.supports('db.query'), isTrue);
      expect(p.supports('db.getTableSchema'), isFalse);
      expect(p.supports('commands.execute'), isFalse);
    });

    test('0.4.18 adds table schema and commands', () {
      final p = ExtensionProtocolProfile.forTarget('0.4.18');
      expect(p.supports('db.getTableSchema'), isTrue);
      expect(p.supports('commands.execute'), isTrue);
    });

    test('0.5.0 speaks everything the current host sends', () {
      final p = ExtensionProtocolProfile.forTarget('0.5.0');
      expect(p.methods.length, 11);
    });

    test('levels distinguish required from recommended methods', () {
      final p = ExtensionProtocolProfile.forTarget('0.5.0');
      expect(p.levelOf('db.connect'), HarnessMethodLevel.required);
      expect(p.levelOf('db.getCapabilities'), HarnessMethodLevel.recommended);
      expect(p.levelOf('db.unknown'), isNull);
    });

    test('hosts before the extension protocol are rejected', () {
      expect(
        () => ExtensionProtocolProfile.forTarget('0.4.10'),
        throwsArgumentError,
      );
    });
  });
}
