import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';

void main() {
  // The lexer reads the input by offset with precompiled patterns (#1527,
  // #1512); these pin the keyword boundaries and operators it has to keep.
  group('GridFilterEngine tokenizer', () {
    const columns = ['id', 'name', 'price', 'note'];
    const rows = [
      ['1', 'Anna', '10', 'x'],
      ['2', 'Andy', '20', 'NULL'],
      ['3', 'Bob', '30', ''],
      ['4', 'Notebook', '40', 'y'],
      ['5', 'Android', '50', 'z'],
    ];

    List<int> run(String filter) => GridFilterEngine.filterRowIndices(
          filterText: filter,
          columns: columns,
          rows: rows,
        );

    test('AND / OR / NOT are keywords only on a word boundary', () {
      expect(run('android'), [4]); // not AND + roid
      expect(run('note'), [3]); // not NOT + e
      expect(run('name = Bob AND price > 10'), [2]);
      expect(run('Bob and price > 10'), [2]);
      expect(run('price < 20 or name = Bob'), [0, 2]);
    });

    test('symbolic operators && || ! work without spaces around names', () {
      expect(run('price>=30 && name:o'), [2, 3, 4]);
      expect(run('price<20 || name = Bob'), [0, 2]);
      expect(run('!name = Bob'), [0, 1, 3, 4]);
      expect(run('NOT name = Bob'), [0, 1, 3, 4]);
    });

    test('comparison operators without spaces', () {
      expect(run('price>=30'), [2, 3, 4]);
      expect(run('price<>30'), [0, 1, 3, 4]);
      expect(run('price!=30'), [0, 1, 3, 4]);
      expect(run('name:an'), [0, 1, 4]);
    });

    test('IS NULL / IS NOT NULL in any case', () {
      expect(run('note IS NULL'), [1, 2]);
      expect(run('note is not null'), [0, 3, 4]);
      expect(run('name IS NULL'), isEmpty);
    });

    test('IN, NOT IN and BETWEEN', () {
      expect(run("name IN ('anna', \"BOB\")"), [0, 2]);
      expect(run('name NOT IN (Anna, Bob)'), [1, 3, 4]);
      expect(run('name IN(Anna)'), [0]);
      expect(run('price BETWEEN 15 AND 40'), [1, 2, 3]);
      expect(run('price between 15 and 40'), [1, 2, 3]);
    });

    test('LIKE, ILIKE and NOT LIKE', () {
      expect(run("name LIKE 'An%'"), [0, 1, 4]);
      expect(run("name ILIKE 'an%'"), [0, 1, 4]);
      expect(run("name LIKE 'an%'"), isEmpty);
      expect(run("name NOT LIKE 'An%'"), [2, 3]);
    });

    test('parentheses group predicates', () {
      expect(run('(price<20 OR price>40) AND note != y'), [0, 4]);
    });
  });
}
