import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/platform/macos_sandbox.dart';

void main() {
  group('MacOsSandbox (#1593)', () {
    tearDown(() => MacOsSandbox.debugOverride = null);

    test('the container id marks a sandboxed process', () {
      expect(
        MacOsSandbox.detect(const {'APP_SANDBOX_CONTAINER_ID': 'com.queryahub.querya'}),
        isTrue,
      );
    });

    test('a HOME inside ~/Library/Containers marks it too', () {
      expect(
        MacOsSandbox.detect(const {
          'HOME': '/Users/ann/Library/Containers/com.queryahub.querya/Data',
        }),
        isTrue,
      );
    });

    test('an ordinary environment is not sandboxed', () {
      expect(MacOsSandbox.detect(const {'HOME': '/Users/ann'}), isFalse);
      expect(MacOsSandbox.detect(const {'APP_SANDBOX_CONTAINER_ID': ''}), isFalse);
      expect(MacOsSandbox.detect(const {}), isFalse);
    });

    test('isActive is false off macOS and can be forced for tests', () {
      if (!Platform.isMacOS) expect(MacOsSandbox.isActive, isFalse);
      MacOsSandbox.debugOverride = true;
      expect(MacOsSandbox.isActive, isTrue);
    });

    test('the message names the feature and the way out', () {
      final text = MacOsSandbox.unavailable('The MCP server');
      expect(text, startsWith('The MCP server is not available'));
      expect(text, contains('release build'));
    });
  });
}
