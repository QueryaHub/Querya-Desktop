import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1487: the dev container has to build with the Flutter version CI uses,
/// otherwise "works in the container" and "passes in CI" drift apart.
void main() {
  test('the dev container Dockerfile pins the Flutter version of ci.yml', () {
    final dockerfile = File('.devcontainer/Dockerfile').readAsStringSync();
    final arg = RegExp(r'^ARG FLUTTER_VERSION=(\S+)$', multiLine: true)
        .firstMatch(dockerfile);
    expect(arg, isNotNull, reason: 'ARG FLUTTER_VERSION= not found');

    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final versions = RegExp(r"flutter-version:\s*'([^']+)'")
        .allMatches(ci)
        .map((m) => m.group(1)!)
        .toSet();

    expect(versions, isNotEmpty, reason: 'no flutter-version in ci.yml');
    expect(
      versions,
      {arg!.group(1)},
      reason: 'ci.yml uses $versions, .devcontainer/Dockerfile pins '
          '${arg.group(1)}: change them together',
    );
  });
}
