import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `querya-ext-tester` is built by `scripts/ci/build_ext_tester.sh` from
/// `lib/core/extensions` and `package:path` alone, in a throwaway package. An
/// import of Flutter or of anything outside that folder breaks the release
/// build, and no other job builds the tester: beta.2 stopped on `logIgnored`.
void main() {
  test('the tester imports only dart:, package:path and core/extensions', () {
    final importRe = RegExp(r'''^import\s+'([^']+)';''', multiLine: true);
    final seen = <String>{};
    final queue = <String>['bin/querya_ext_tester.dart'];
    final bad = <String>[];

    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!seen.add(file)) continue;
      final text = File(file).readAsStringSync();
      for (final m in importRe.allMatches(text)) {
        final uri = m.group(1)!;
        if (uri.startsWith('dart:') || uri.startsWith('package:path/')) {
          continue;
        }
        const own = 'package:querya_desktop/';
        if (uri.startsWith('${own}core/extensions/')) {
          queue.add('lib/${uri.substring(own.length)}');
        } else {
          bad.add('$file imports $uri');
        }
      }
    }

    expect(bad, isEmpty, reason: bad.join('\n'));
    expect(seen.length, greaterThan(3));
  });
}
