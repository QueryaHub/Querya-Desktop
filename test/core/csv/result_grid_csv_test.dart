import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/csv/result_grid_csv.dart';

void main() {
  group('resultGridAsCsv', () {
    test('escapes commas and quotes', () {
      expect(
        resultGridAsCsv(
          const ['a', 'b'],
          const [
            ['1', 'two,comma'],
            ['quote', 'say "hi"'],
          ],
        ),
        'a,b\n1,"two,comma"\nquote,"say ""hi"""',
      );
    });

    test('pads short rows', () {
      expect(
        resultGridAsCsv(const ['x', 'y', 'z'], const [
          ['only'],
        ]),
        'x,y,z\nonly,,',
      );
    });
  });
}
