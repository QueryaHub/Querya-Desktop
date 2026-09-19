import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_script_format.dart';

void main() {
  test('uppercases SQL keywords and leaves identifiers', () {
    expect(
      formatSqlScript('select id from users where name = \'Ada\''),
      "SELECT id FROM users WHERE name = 'Ada'",
    );
  });
}
