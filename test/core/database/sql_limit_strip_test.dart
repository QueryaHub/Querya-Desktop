import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';

/// `stripLeadingWhitespaceAndLineComments` before #1515: one substring + trimLeft
/// per comment, the reference the offset scanner has to match.
String _reference(String sql) {
  int blockEnd(String s, int start) {
    var depth = 0;
    var i = start;
    while (i < s.length) {
      if (s.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (s.startsWith('*/', i)) {
        depth--;
        i += 2;
        if (depth == 0) return i;
      } else {
        i++;
      }
    }
    return s.length;
  }

  var s = sql.trimLeft();
  while (true) {
    if (s.isEmpty) return s;
    if (s.startsWith('--')) {
      final nl = s.indexOf('\n');
      if (nl == -1) return '';
      s = s.substring(nl + 1).trimLeft();
      continue;
    }
    if (s.startsWith('/*')) {
      s = s.substring(blockEnd(s, 0)).trimLeft();
      continue;
    }
    return s;
  }
}

void main() {
  group('stripLeadingWhitespaceAndLineComments offset scanner (#1515)', () {
    test('agrees with the previous implementation on listed scripts', () {
      const cases = <String>[
        '',
        ' ',
        '\n\t \r\n',
        'SELECT 1',
        '  SELECT 1',
        '-- c\nSELECT 1',
        '-- c\r\nSELECT 1',
        '-- c\n-- d\n\n  -- e\nSELECT 1',
        '-- only a comment',
        '-- c\n',
        '/* c */SELECT 1',
        '/* a */ /* b */\n  SELECT 1',
        '/* a /* nested */ still */ SELECT 1',
        '/* unterminated',
        '/* a */ -- b\n/* c */ SELECT 1',
        '--\nSELECT 1',
        '-',
        '/',
        'SELECT 1 -- trailing\nFROM t',
        '  ﻿-- c\nSELECT 1',
        '\u0085SELECT 1',
        '᠎SELECT 1',
        '/*/ x */ SELECT 1',
        '/**/SELECT 1',
      ];
      for (final sql in cases) {
        expect(
          stripLeadingWhitespaceAndLineComments(sql),
          _reference(sql),
          reason: sql,
        );
      }
    });

    test('agrees with the previous implementation on random scripts', () {
      const pieces = <String>[
        '--', '/*', '*/', '\n', '\r\n', ' ', '\t', ' ', '﻿',
        'SELECT', '1', 'x', '-', '/', '*',
      ];
      final random = Random(1515);
      for (var n = 0; n < 4000; n++) {
        final sql = [
          for (var k = random.nextInt(24); k > 0; k--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        expect(
          stripLeadingWhitespaceAndLineComments(sql),
          _reference(sql),
          reason: sql,
        );
      }
    });

    test('a long comment header in front of a large script is one pass', () {
      final header = List.generate(500, (i) => '-- header line $i').join('\n');
      final body = 'SELECT ${List.filled(20000, 'col').join(', ')} FROM t';
      final sql = '$header\n$body';
      expect(stripLeadingWhitespaceAndLineComments(sql), body);
    });
  });
}
