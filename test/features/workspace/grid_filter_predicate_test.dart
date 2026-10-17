import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';

void main() {
  // A predicate resolves its operator, target, IN set and BETWEEN bounds once
  // when it is built (#1550); these pin the per-row results.
  group('GridFilterEngine predicates', () {
    const columns = ['id', 'name', 'price', 'note'];
    const rows = [
      ['1', 'Anna', '10', 'x'],
      ['2', 'Andy', '20.0', 'NULL'],
      ['3', 'Bob', '30', ''],
      ['4', 'Notebook', '40', 'y'],
      ['5', 'Android', '50', 'z'],
    ];

    List<int> run(String filter) => GridFilterEngine.filterRowIndices(
          filterText: filter,
          columns: columns,
          rows: rows,
        );

    test('IN compares trimmed, case-insensitive values', () {
      expect(run("name IN (' ANNA ', bob)"), [0, 2]);
      expect(run('name IN (anDY, "NOTEBOOK")'), [1, 3]);
      expect(run("name NOT IN (' anna ', BOB)"), [1, 3, 4]);
      expect(run('price IN (10, 30)'), [0, 2]); // "20.0" is not in the list
    });

    test('BETWEEN is numeric when all three sides are numbers', () {
      expect(run('price BETWEEN 15 AND 40'), [1, 2, 3]);
      expect(run('price BETWEEN 20 AND 20'), [1]);
    });

    test('BETWEEN falls back to a case-sensitive string range', () {
      expect(run("name BETWEEN 'Anna' AND 'Bob'"), [0, 2]);
    });

    test('numeric comparison needs both sides to parse', () {
      expect(run('price = 20'), [1]); // "20.0" equals 20
      expect(run('price > 25'), [2, 3, 4]);
      expect(run('price <= 20'), [0, 1]);
      expect(run('price = abc'), isEmpty);
    });

    test('string comparison and contains ignore case', () {
      expect(run('name = ANNA'), [0]);
      expect(run('name : ND'), [1, 4]);
      expect(run('name != bob'), [0, 1, 3, 4]);
      expect(run('name > Bob'), [3]); // "notebook" > "bob"
    });

    test('a number target compares numerically, a text target as text', () {
      expect(run('id = 3'), [2]);
      expect(run('price : 20'), [1]); // `:` is equality between two numbers
      expect(run('price >= 30'), [2, 3, 4]);
      expect(run('name = 10'), isEmpty); // text cells against a number
      expect(run('price = abc'), isEmpty); // number cells against text
    });

    test('free text is case-insensitive in every column', () {
      expect(run('ANDROID'), [4]);
      expect(run('NOTEBOOK x'), isEmpty); // both terms must hit some column
      expect(run('anna X'), [0]);
    });

    test('IS NULL treats NULL, null and empty as null', () {
      expect(run('note IS NULL'), [1, 2]);
      expect(run('note IS NOT NULL'), [0, 3, 4]);
    });
  });
}
