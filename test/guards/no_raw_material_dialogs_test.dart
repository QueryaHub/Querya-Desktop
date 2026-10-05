import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1039: Raw Material AlertDialog must not be used directly in `lib/`.
/// All dialogs must use QueryaModalDialog or QueryaConfirmDialog.
void main() {
  test('no raw Material AlertDialog in lib/', () {
    final banned = RegExp(r'\b(material\.)?AlertDialog\b');
    final offenders = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final content = f.readAsStringSync();
      if (banned.hasMatch(content)) {
        offenders.add(f.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Found raw AlertDialog in the following files: $offenders. '
          'Use QueryaModalDialog or QueryaConfirmDialog instead.',
    );
  });
}
