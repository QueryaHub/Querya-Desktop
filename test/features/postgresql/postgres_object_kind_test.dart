import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';

void main() {
  group('PostgresObjectKind', () {
    test('includes all browser object variants', () {
      expect(
        PostgresObjectKind.values.map((e) => e.name).toSet(),
        equals({
          'table',
          'view',
          'materializedView',
          'function',
          'sequence',
          'schemaIndexes',
          'schemaTriggers',
          'schemaTypes',
          'databaseExtensions',
          'databaseForeignData',
        }),
      );
    });

    test('materializedView and schema metadata kinds are distinct', () {
      expect(PostgresObjectKind.materializedView, isNot(PostgresObjectKind.view));
      expect(PostgresObjectKind.schemaIndexes, isNot(PostgresObjectKind.schemaTriggers));
      expect(PostgresObjectKind.databaseExtensions, isNot(PostgresObjectKind.databaseForeignData));
    });
  });
}
