import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';

void main() {
  group('replaceDatabaseInMysqlConnectionString', () {
    test('replaces path segment', () {
      expect(
        replaceDatabaseInMysqlConnectionString(
          'mysql://u:p@h:3306/olddb',
          'newdb',
        ),
        'mysql://u:p@h:3306/newdb',
      );
    });

    test('replaces database query param', () {
      expect(
        replaceDatabaseInMysqlConnectionString(
          'mysql://h:3306/?database=old',
          'new',
        ),
        contains('database=new'),
      );
    });

    test('throws on wrong scheme', () {
      expect(
        () => replaceDatabaseInMysqlConnectionString('postgres://h/db', 'x'),
        throwsArgumentError,
      );
    });
  });

  group('MysqlConnection.quoteIdentifier', () {
    test('escapes backticks', () {
      expect(
        MysqlConnection.quoteIdentifier('a`b'),
        '`a``b`',
      );
    });
  });
}
