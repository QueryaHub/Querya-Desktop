import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1039: Raw Material CircularProgressIndicator must not be used directly in `lib/`
/// outside of `QueryaSpinner` (`lib/shared/widgets/querya_spinner.dart`).
void main() {
  test('no raw CircularProgressIndicator in lib/ outside of QueryaSpinner', () {
    final banned = RegExp(r'\b(material\.)?CircularProgressIndicator\b');
    final offenders = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('lib/shared/widgets/querya_spinner.dart')) continue;

      final content = f.readAsStringSync();
      if (banned.hasMatch(content)) {
        offenders.add(f.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Found raw CircularProgressIndicator in the following files: $offenders. '
          'Use QueryaSpinner from lib/shared/widgets/widgets.dart instead.',
    );
  });
}
