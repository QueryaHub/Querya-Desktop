import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';

void main() {
  group('DestructiveSqlDetector', () {
    test('detects DROP DATABASE', () {
      final res = DestructiveSqlDetector.inspect('DROP DATABASE production;');
      expect(res.isDestructive, isTrue);
      expect(res.operations.length, 1);
      expect(res.operations.first.type, DestructiveSqlType.dropDatabase);
      expect(res.operations.first.targetName, 'production');
      expect(res.maxRiskLevel, 'CRITICAL');
    });

    test('detects DROP DATABASE IF EXISTS with backticks', () {
      final res = DestructiveSqlDetector.inspect('DROP DATABASE IF EXISTS `analytics_db`');
      expect(res.isDestructive, isTrue);
      expect(res.operations.first.type, DestructiveSqlType.dropDatabase);
      expect(res.operations.first.targetName, 'analytics_db');
    });

    test('detects DROP SCHEMA', () {
      final res = DestructiveSqlDetector.inspect('DROP SCHEMA public CASCADE;');
      expect(res.isDestructive, isTrue);
      expect(res.operations.first.type, DestructiveSqlType.dropSchema);
      expect(res.operations.first.targetName, 'public');
    });

    test('detects DROP TABLE', () {
      final res = DestructiveSqlDetector.inspect('DROP TABLE users;');
      expect(res.isDestructive, isTrue);
      expect(res.operations.first.type, DestructiveSqlType.dropTable);
      expect(res.operations.first.targetName, 'users');
    });

    test('detects DROP TABLE with schema and quotes', () {
      final res = DestructiveSqlDetector.inspect('DROP TABLE IF EXISTS "public"."orders";');
      expect(res.isDestructive, isTrue);
      expect(res.operations.first.type, DestructiveSqlType.dropTable);
      expect(res.operations.first.targetName, 'public.orders');
    });

    test('detects DROP VIEW and DROP MATERIALIZED VIEW', () {
      final viewRes = DestructiveSqlDetector.inspect('DROP VIEW monthly_report;');
      expect(viewRes.isDestructive, isTrue);
      expect(viewRes.operations.first.type, DestructiveSqlType.dropView);
      expect(viewRes.operations.first.targetName, 'monthly_report');

      final matRes = DestructiveSqlDetector.inspect('DROP MATERIALIZED VIEW public.active_users;');
      expect(matRes.isDestructive, isTrue);
      expect(matRes.operations.first.type, DestructiveSqlType.dropMaterializedView);
      expect(matRes.operations.first.targetName, 'public.active_users');
    });

    test('detects TRUNCATE and TRUNCATE TABLE', () {
      final t1 = DestructiveSqlDetector.inspect('TRUNCATE TABLE session_logs;');
      expect(t1.isDestructive, isTrue);
      expect(t1.operations.first.type, DestructiveSqlType.truncateTable);
      expect(t1.operations.first.targetName, 'session_logs');

      final t2 = DestructiveSqlDetector.inspect('TRUNCATE analytics.events;');
      expect(t2.isDestructive, isTrue);
      expect(t2.operations.first.type, DestructiveSqlType.truncateTable);
      expect(t2.operations.first.targetName, 'analytics.events');
    });

    test('detects unconditional DELETE FROM', () {
      final res = DestructiveSqlDetector.inspect('DELETE FROM users;');
      expect(res.isDestructive, isTrue);
      expect(res.operations.first.type, DestructiveSqlType.unconditionalDelete);
      expect(res.operations.first.targetName, 'users');
    });

    test('does NOT mark DELETE with WHERE clause as unconditionalDelete', () {
      final res = DestructiveSqlDetector.inspect('DELETE FROM users WHERE id = 123;');
      expect(res.isDestructive, isFalse);
    });

    test('handles multi-statement scripts containing destructive actions', () {
      const sql = '''
        SELECT * FROM users WHERE active = true;
        INSERT INTO audit_log VALUES (1, 'checking');
        DROP TABLE temp_import_data;
        SELECT 1;
      ''';
      final res = DestructiveSqlDetector.inspect(sql);
      expect(res.isDestructive, isTrue);
      expect(res.operations.length, 1);
      expect(res.operations.first.type, DestructiveSqlType.dropTable);
      expect(res.operations.first.targetName, 'temp_import_data');
    });

    test('ignores destructive keywords inside single-quoted strings', () {
      final res = DestructiveSqlDetector.inspect("INSERT INTO logs (msg) VALUES ('DROP TABLE users;');");
      expect(res.isDestructive, isFalse);
    });

    test('ignores destructive keywords inside dollar-quoted strings', () {
      final res = DestructiveSqlDetector.inspect(r'''
        CREATE OR REPLACE FUNCTION clean_data() RETURNS void AS $$
        BEGIN
          -- Some logic
        END;
        $$ LANGUAGE plpgsql;
      ''');
      expect(res.isDestructive, isFalse);
    });

    test('ignores destructive keywords inside line comments', () {
      final res = DestructiveSqlDetector.inspect('''
        -- DROP TABLE users;
        SELECT * FROM users;
      ''');
      expect(res.isDestructive, isFalse);
    });

    test('ignores destructive keywords inside block comments', () {
      final res = DestructiveSqlDetector.inspect('''
        /*
         * TRUNCATE TABLE orders;
         * DROP DATABASE prod;
         */
        SELECT count(*) FROM orders;
      ''');
      expect(res.isDestructive, isFalse);
    });

    test('returns non-destructive for regular queries', () {
      expect(DestructiveSqlDetector.inspect('SELECT * FROM users').isDestructive, isFalse);
      expect(DestructiveSqlDetector.inspect('CREATE TABLE items (id INT);').isDestructive, isFalse);
      expect(DestructiveSqlDetector.inspect('ALTER TABLE users ADD COLUMN age INT;').isDestructive, isFalse);
      expect(DestructiveSqlDetector.inspect('UPDATE users SET age = 20 WHERE id = 1;').isDestructive, isFalse);
    });
  });
}
