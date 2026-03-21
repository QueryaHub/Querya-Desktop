import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/postgres_sql.dart';

void main() {
  group('stripLeadingWhitespaceAndLineComments', () {
    test('strips leading line comments', () {
      expect(
        stripLeadingWhitespaceAndLineComments('-- c\nBEGIN'),
        'BEGIN',
      );
    });

    test('strips multiple line comments', () {
      expect(
        stripLeadingWhitespaceAndLineComments('-- a\n-- b\nSELECT 1'),
        'SELECT 1',
      );
    });

    test('empty after only comments becomes empty string', () {
      expect(stripLeadingWhitespaceAndLineComments('-- only'), '');
    });

    test('leading whitespace then SQL', () {
      expect(
        stripLeadingWhitespaceAndLineComments('  \n  SELECT 1'),
        'SELECT 1',
      );
    });
  });

  group('shouldSkipImplicitBegin', () {
    test('detects BEGIN', () {
      expect(shouldSkipImplicitBegin('BEGIN'), isTrue);
      expect(shouldSkipImplicitBegin('  begin '), isTrue);
    });

    test('detects BEGIN WORK', () {
      expect(shouldSkipImplicitBegin('BEGIN WORK'), isTrue);
    });

    test('detects START TRANSACTION', () {
      expect(shouldSkipImplicitBegin('START TRANSACTION'), isTrue);
    });

    test('detects COMMIT and ROLLBACK', () {
      expect(shouldSkipImplicitBegin('COMMIT'), isTrue);
      expect(shouldSkipImplicitBegin('ROLLBACK'), isTrue);
    });

    test('detects SAVEPOINT and RELEASE SAVEPOINT', () {
      expect(shouldSkipImplicitBegin('SAVEPOINT sp'), isTrue);
      expect(shouldSkipImplicitBegin('RELEASE SAVEPOINT sp'), isTrue);
    });

    test('detects PREPARE / COMMIT PREPARED', () {
      expect(shouldSkipImplicitBegin('PREPARE TRANSACTION'), isTrue);
      expect(shouldSkipImplicitBegin('COMMIT PREPARED'), isTrue);
      expect(shouldSkipImplicitBegin('ROLLBACK PREPARED'), isTrue);
    });

    test('detects END', () {
      expect(shouldSkipImplicitBegin('END'), isTrue);
    });

    test('allows plain SELECT', () {
      expect(shouldSkipImplicitBegin('SELECT 1'), isFalse);
    });

    test('after line comments, first statement is used', () {
      expect(
        shouldSkipImplicitBegin('-- note\nSELECT 1'),
        isFalse,
      );
    });

    test('allows INSERT/UPDATE without implicit begin skip', () {
      expect(shouldSkipImplicitBegin('INSERT INTO t VALUES (1)'), isFalse);
      expect(shouldSkipImplicitBegin('UPDATE t SET x = 1'), isFalse);
    });
  });
}
