import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mysql/mysql_table_utils.dart';

void main() {
  group('isAllowedMysqlSelectQuery', () {
    test('allows single SELECT', () {
      expect(isAllowedMysqlSelectQuery('SELECT * FROM t'), isTrue);
    });

    test('allows WITH', () {
      expect(isAllowedMysqlSelectQuery('WITH x AS (SELECT 1) SELECT * FROM x'), isTrue);
    });

    test('rejects multi-statement', () {
      expect(isAllowedMysqlSelectQuery('SELECT 1; SELECT 2'), isFalse);
    });

    test('rejects empty', () {
      expect(isAllowedMysqlSelectQuery(''), isFalse);
    });
  });
}
