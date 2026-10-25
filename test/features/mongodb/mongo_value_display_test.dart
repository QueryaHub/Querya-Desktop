import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show BsonBinary, ObjectId;
import 'package:querya_desktop/features/mongodb/mongo_value_display.dart';

/// Stand-ins for the driver's `Int64` (fixnum) and `Decimal` (decimal), which
/// the app does not depend on directly: the display code goes by type name.
class Int64 {
  const Int64(this.v);
  final int v;
  @override
  String toString() => '$v';
}

class Decimal {
  const Decimal(this.v);
  final String v;
  @override
  String toString() => v;
}

void main() {
  test('binary reads as Binary(0x…), not BsonBinary(…)', () {
    expect(mongoValueText(BsonBinary.from([0xde, 0xad, 0xbe, 0xef])),
        'Binary(0xdeadbeef)');
    expect(mongoValueText(BsonBinary.from(const [])), 'Binary(0x)');
    expect(mongoValueTypeChip(BsonBinary.from([1])), 'bin');
    expect(mongoValueTypeName(BsonBinary.from([1])), 'Binary');
  });

  test('a regular expression reads as /pattern/flags', () {
    expect(mongoValueText(RegExp('^querya')), '/^querya/');
    expect(mongoValueText(RegExp('^querya', caseSensitive: false)), '/^querya/i');
    expect(mongoValueText(RegExp('a', multiLine: true, caseSensitive: false)),
        '/a/im');
    expect(mongoValueTypeChip(RegExp('a')), 'regex');
    // The private Dart class name never reaches the screen.
    expect(mongoValueTypeName(RegExp('a')), 'Regex');
  });

  test('Int64 and Decimal are numbers with their own chips', () {
    expect(mongoValueIsNumber(const Int64(9223372036854775807)), isTrue);
    expect(mongoValueIsNumber(const Decimal('12345678901234.5678')), isTrue);
    expect(mongoValueIsNumber(1), isTrue);
    expect(mongoValueIsNumber(1.5), isTrue);
    expect(mongoValueIsNumber('1'), isFalse);
    expect(mongoValueIsNumber(null), isFalse);
    expect(mongoValueTypeChip(const Int64(1)), 'long');
    expect(mongoValueTypeChip(const Decimal('1.5')), 'dec');
    expect(mongoValueText(const Int64(7)), '7');
  });

  test('the other chips are unchanged', () {
    expect(mongoValueTypeChip(null), 'null');
    expect(mongoValueTypeChip('x'), 'str');
    expect(mongoValueTypeChip(1), 'int');
    expect(mongoValueTypeChip(1.5), 'dbl');
    expect(mongoValueTypeChip(true), 'bool');
    expect(mongoValueTypeChip(ObjectId()), 'oid');
    expect(mongoValueTypeChip(DateTime.utc(2026)), 'date');
  });
}
