import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';

void main() {
  group('SqlTableTargetExtractor', () {
    test('extracts table name from simple SELECT', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM users');
      expect(target, isNotNull);
      expect(target!.tableName, 'users');
      expect(target.schema, isNull);
    });

    test('extracts schema and table from quoted identifiers', () {
      final target = SqlTableTargetExtractor.extract('SELECT id, name FROM "public"."accounts" WHERE id > 10');
      expect(target, isNotNull);
      expect(target!.tableName, 'accounts');
      expect(target.schema, 'public');
    });

    test('extracts schema and table from MySQL backticks', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM `shop_db`.`orders` ORDER BY date DESC');
      expect(target, isNotNull);
      expect(target!.tableName, 'orders');
      expect(target.schema, 'shop_db');
    });

    test('returns null for queries with JOINs to avoid ambiguous mutations', () {
      final target = SqlTableTargetExtractor.extract('SELECT u.id, o.amount FROM users u JOIN orders o ON u.id = o.user_id');
      expect(target, isNull);
    });

    test('returns null for empty or non-FROM queries', () {
      expect(SqlTableTargetExtractor.extract(''), isNull);
      expect(SqlTableTargetExtractor.extract('SELECT 1 + 1'), isNull);
    });
  });
}
