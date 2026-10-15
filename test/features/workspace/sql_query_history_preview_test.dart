import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/sql_query_history_dialog.dart';

/// The implementation before #1545: collapse the whole text, then cut.
String _reference(String sql) {
  final collapsed = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= 96) return collapsed;
  return '${collapsed.substring(0, 93)}…';
}

void main() {
  group('previewSqlOneLine (#1545)', () {
    test('matches the old collapse-then-cut result', () {
      final inputs = <String>[
        '',
        ' ',
        '   \n\t  ',
        'SELECT 1',
        '  SELECT   1 \n FROM\tt  ',
        'SELECT a, b　FROM t',
        'a' * 96,
        'a' * 97,
        '${'a' * 96}   ',
        '${'a' * 96} b',
        '${'a' * 95} b',
        '${'a' * 94} b c',
        ('select x from t\n' * 20),
        '\n\n\n${'x ' * 200}',
        'a' * 5000,
        'word ' * 30000,
      ];
      for (final sql in inputs) {
        expect(previewSqlOneLine(sql), _reference(sql),
            reason: 'input of length ${sql.length}');
      }
    });

    test('long text is cut to 93 characters and an ellipsis', () {
      final out = previewSqlOneLine('SELECT ${'column_name, ' * 100}FROM t');
      expect(out.length, 94);
      expect(out.endsWith('…'), isTrue);
    });
  });
}
