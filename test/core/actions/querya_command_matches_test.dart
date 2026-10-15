import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';

void main() {
  final command = QueryaCommand(
    id: 'querya.sql.formatDocument',
    title: 'Format SQL',
    category: 'Editor',
    aliases: const ['Beautify', 'pretty print'],
    execute: (_) {},
  );

  group('QueryaCommand.matches (#1528)', () {
    test('blank query matches', () {
      expect(command.matches(''), isTrue);
      expect(command.matches('   '), isTrue);
    });

    test('title, id, id tail, category and aliases match, any case', () {
      expect(command.matches('FORMAT'), isTrue);
      expect(command.matches('querya.sql'), isTrue);
      expect(command.matches('formatdocument'), isTrue);
      expect(command.matches('editor'), isTrue);
      expect(command.matches('beautify'), isTrue);
      expect(command.matches('pretty'), isTrue);
    });

    test('every whitespace-separated part must match, in any field', () {
      expect(command.matches('format editor'), isTrue);
      expect(command.matches('  beautify   sql '), isTrue);
      expect(command.matches('format nothing'), isFalse);
    });

    test('a part does not match across two fields', () {
      // "Format SQL" ends in "sql", the id tail starts with "format".
      expect(command.matches('sqlformat'), isFalse);
      expect(command.matches('sqlquerya'), isFalse);
    });

    test('matchesParts agrees with matches for pre-split queries', () {
      for (final q in ['', 'format', 'Format  EDITOR', 'zzz', 'pretty print']) {
        expect(
          command.matchesParts(QueryaCommand.queryParts(q)),
          command.matches(q),
          reason: q,
        );
      }
    });

    test('an id without a dot uses the whole id as its tail', () {
      final c = QueryaCommand(id: 'plain', title: 'T', execute: (_) {});
      expect(c.matches('plain'), isTrue);
    });
  });

  group('filterSchemaObjects haystack cache (#1528)', () {
    test('the lower-cased haystack is stable and case-insensitive', () {
      final o = QueryaSchemaObject.postgres(
        database: 'Sales',
        schema: 'Public',
        name: 'Users',
        kind: QueryaSchemaObjectKind.table,
      );
      expect(identical(o.searchHaystackLower, o.searchHaystackLower), isTrue);
      expect(o.searchHaystackLower, o.searchHaystack.toLowerCase());
      expect(filterSchemaObjects([o], 'PUBLIC.users'), [o]);
      expect(filterSchemaObjects([o], 'orders'), isEmpty);
    });
  });
}
