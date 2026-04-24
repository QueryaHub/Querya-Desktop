import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/json/result_grid_json.dart';

void main() {
  group('resultGridAsJson', () {
    test('encodes columns and rows', () {
      final s = resultGridAsJson(
        const ['a', 'b'],
        const [
          ['1', 'two'],
          ['x', 'y'],
        ],
      );
      expect(jsonDecode(s), {
        'columns': ['a', 'b'],
        'rows': [
          ['1', 'two'],
          ['x', 'y'],
        ],
      });
    });

    test('escapes strings for JSON', () {
      final s = resultGridAsJson(
        const ['q'],
        const [
          ['say "hi"'],
          ['line\nbreak'],
        ],
      );
      expect(jsonDecode(s), {
        'columns': ['q'],
        'rows': [
          ['say "hi"'],
          ['line\nbreak'],
        ],
      });
    });

    test('pads short rows', () {
      final s = resultGridAsJson(const ['x', 'y', 'z'], const [
        ['only'],
      ]);
      expect(jsonDecode(s), {
        'columns': ['x', 'y', 'z'],
        'rows': [
          ['only', '', ''],
        ],
      });
    });
  });
}
