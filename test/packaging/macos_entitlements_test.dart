import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1592: what ships for macOS (the Xcode Release configuration when there are
/// no signing secrets, ReleaseSigned when there are) has no App Sandbox.
void main() {
  const sandbox = 'com.apple.security.app-sandbox';

  test('the Xcode Release configuration uses ReleaseUnsigned.entitlements',
      () {
    final project =
        File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final release = RegExp(
      r'/\* Release \*/ = \{\s*isa = XCBuildConfiguration;'
      r'[^}]*?CODE_SIGN_ENTITLEMENTS = ([^;]+);',
    ).allMatches(project).map((m) => m[1]).toList();
    expect(release, ['Runner/ReleaseUnsigned.entitlements']);
  });

  for (final name in ['ReleaseUnsigned', 'ReleaseSigned']) {
    test('$name.entitlements has no App Sandbox', () {
      final text =
          File('macos/Runner/$name.entitlements').readAsStringSync();
      expect(text, isNot(contains(sandbox)));
    });
  }
}
