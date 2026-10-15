import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/results/charts/chart_data.dart';

/// `ChartData.parseTime` before #1514 (regex, replaceFirst, substrings): the
/// reference the code-unit version has to agree with.
final _isoTime = RegExp(
  r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?(Z|[+-]\d{2}:?\d{2})?$',
);
final _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

DateTime? _reference(String raw) {
  final text = raw.trim();
  if (!_isoTime.hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (parsed == null) return null;
  if (parsed.year != int.parse(text.substring(0, 4)) ||
      parsed.month != int.parse(text.substring(5, 7)) ||
      parsed.day != int.parse(text.substring(8, 10))) {
    return null;
  }
  if (text.length >= 16 &&
      (parsed.hour != int.parse(text.substring(11, 13)) ||
          parsed.minute != int.parse(text.substring(14, 16)))) {
    return null;
  }
  if (_hasZone.hasMatch(text)) return parsed.toUtc();
  return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
      parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}

void main() {
  group('ChartData.parseTime scanner (#1514)', () {
    test('agrees with the previous implementation on listed values', () {
      const cases = <String>[
        '',
        ' ',
        '2026-01-31',
        ' 2026-01-31 ',
        '2026-01-31 10:30',
        '2026-01-31T10:30',
        '2026-01-31T10:30:15',
        '2026-01-31T10:30:15.123',
        '2026-01-31T10:30:15.123456',
        '2026-01-31T10:30:15.',
        '2026-01-31T10:30:1',
        '2026-01-31T10:3',
        '2026-01-31T10',
        '2026-01-31T10:30Z',
        '2026-01-31T10:30:00Z',
        '2026-01-31 10:30:00+02:00',
        '2026-01-31 10:30:00-0530',
        '2026-01-31 10:30:00+02',
        '2026-01-31 10:30:00 +02:00',
        '2026-01-31Z',
        '2026-01-31+01:00',
        '2026-01-31+0100',
        '2026-13-45',
        '2026-02-30',
        '2026-02-29',
        '2024-02-29',
        '2026-01-31T25:00',
        '2026-01-31T10:61',
        '2026-01-31T24:00',
        '2026-1-31',
        '26-01-31',
        '31.01.2026',
        '2026/01/31',
        '2026-01-31x',
        '2026-01-31T10:30:00zZ',
        '2026-01-31t10:30',
        '2026-01-31  10:30',
        '0000-01-01',
        '9999-12-31T23:59:59.999Z',
        '２０２６-01-31',
      ];
      for (final raw in cases) {
        expect(ChartData.parseTime(raw), _reference(raw), reason: '"$raw"');
      }
    });

    test('agrees with the previous implementation on random strings', () {
      const pieces = <String>[
        '2026', '2024', '0000', '99', '01', '12', '13', '31', '45', '10', '24',
        '60', '-', ':', '.', ' ', 'T', 'Z', '+', 'z', 't', '5', 'x',
      ];
      final random = Random(1514);
      for (var n = 0; n < 6000; n++) {
        // Mostly shaped like a date, with random pieces dropped and swapped in.
        final parts = <String>[
          '2026', '-', '01', '-', '31',
          if (random.nextBool()) ...[
            random.nextBool() ? 'T' : ' ',
            '10', ':', '30',
            if (random.nextBool()) ...[':', '15'],
            if (random.nextBool()) ...['.', '123'],
          ],
          if (random.nextBool()) ...[
            random.nextBool() ? 'Z' : '+',
            '02', if (random.nextBool()) ':', '00',
          ],
        ];
        for (var k = random.nextInt(3); k > 0; k--) {
          parts[random.nextInt(parts.length)] =
              pieces[random.nextInt(pieces.length)];
        }
        final raw = parts.join();
        expect(ChartData.parseTime(raw), _reference(raw), reason: '"$raw"');
      }
    });

    test('a 100,000 row column is checked in one pass', () {
      final rows = [
        for (var i = 0; i < 100000; i++)
          ['2026-01-${(i % 28 + 1).toString().padLeft(2, '0')} 10:30:00'],
      ];
      expect(ChartData.isTimeColumn(rows, 0), isTrue);
      rows.add(['not a date']);
      expect(ChartData.isTimeColumn(rows, 0), isFalse);
    });
  });
}
