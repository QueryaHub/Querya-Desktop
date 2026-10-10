import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/database/postgres_result_cells.dart';
import 'package:querya_desktop/core/database/postgres_value_format.dart';

/// Binary values the driver has no codec for used to reach
/// `UndecodedBytes.asString`, which threw FormatException on them: money,
/// timetz, inet, bit, numrange and composite types broke whole result sets.
UndecodedBytes _binary(int oid, List<int> bytes) => UndecodedBytes(
      typeOid: oid,
      isBinary: true,
      bytes: Uint8List.fromList(bytes),
      encoding: utf8,
    );

List<int> _i16(int v) => (ByteData(2)..setInt16(0, v)).buffer.asUint8List();
List<int> _i32(int v) => (ByteData(4)..setInt32(0, v)).buffer.asUint8List();
List<int> _i64(int v) => (ByteData(8)..setInt64(0, v)).buffer.asUint8List();

String _text(UndecodedBytes v) => postgresUndecodedText(v);

List<int> _numeric(List<int> digits, int weight, int dScale, {int sign = 0}) => [
      ..._i16(digits.length),
      ..._i16(weight),
      ..._i16(sign),
      ..._i16(dScale),
      for (final d in digits) ..._i16(d),
    ];

List<int> _withLen(List<int> bytes) => [..._i32(bytes.length), ...bytes];

void main() {
  group('binary values without a driver codec', () {
    test('money', () {
      expect(_text(_binary(790, _i64(123456))), r'$1,234.56');
      expect(_text(_binary(790, _i64(-5))), r'-$0.05');
    });

    test('numeric', () {
      expect(_text(_binary(1700, _numeric([12, 3456, 7890, 1234, 5678], 3, 4))),
          '12345678901234.5678');
      expect(_text(_binary(1700, _numeric([500], -1, 2, sign: 0x4000))),
          '-0.05');
      expect(_text(_binary(1700, _numeric([], 0, 0))), '0');
    });

    test('timetz', () {
      // 10:30:00, zone 3 h east of UTC (stored as seconds west: -10800).
      final bytes = [..._i64(37800000000), ..._i32(-10800)];
      expect(_text(_binary(1266, bytes)), '10:30:00+03');
    });

    test('inet and cidr', () {
      expect(_text(_binary(869, [2, 8, 0, 4, 10, 0, 0, 1])), '10.0.0.1/8');
      expect(_text(_binary(869, [2, 32, 0, 4, 10, 0, 0, 1])), '10.0.0.1');
      expect(_text(_binary(650, [2, 24, 1, 4, 192, 168, 1, 0])),
          '192.168.1.0/24');
    });

    test('macaddr, macaddr8, oid', () {
      expect(_text(_binary(829, [8, 0, 0x2b, 1, 2, 3])), '08:00:2b:01:02:03');
      expect(_text(_binary(774, [8, 0, 0x2b, 1, 2, 3, 4, 5])),
          '08:00:2b:01:02:03:04:05');
      expect(_text(_binary(26, _i32(16384))), '16384');
    });

    test('bit and varbit', () {
      expect(_text(_binary(1560, [..._i32(5), 0xB0])), '10110');
      expect(_text(_binary(1562, [..._i32(3), 0xA0])), '101');
    });

    test('numrange and int4multirange', () {
      final numrange = [
        0x02, // lower inclusive, upper exclusive
        ..._withLen(_numeric([1, 5000], 0, 1)),
        ..._withLen(_numeric([10], 0, 0)),
      ];
      expect(_text(_binary(3906, numrange)), '[1.5,10)');

      List<int> int4range(int lo, int hi) => [
            0x02,
            ..._withLen(_i32(lo)),
            ..._withLen(_i32(hi)),
          ];
      final multi = [
        ..._i32(2),
        ..._withLen(int4range(1, 10)),
        ..._withLen(int4range(20, 30)),
      ];
      expect(_text(_binary(4451, multi)), '{[1,10),[20,30)}');
      expect(_text(_binary(3904, [0x01])), 'empty');
    });

    test('a composite value reads as a record', () {
      List<int> column(String s) =>
          [..._i32(25), ..._withLen(utf8.encode(s))];
      final record = [
        ..._i32(3),
        ...column('Unter den Linden 1'),
        ...column('Berlin'),
        ..._i32(25),
        ..._i32(-1), // NULL
      ];
      expect(_text(_binary(900001, record)),
          '("Unter den Linden 1",Berlin,)');
    });

    test('an unknown binary type shows as text or hex and never throws', () {
      expect(_text(_binary(999999, utf8.encode('plain'))), 'plain');
      expect(_text(_binary(999999, [0xff, 0xfe, 0x00, 0x01])), r'\xfffe0001');
    });

    test('a value in text format is decoded as text', () {
      final v = UndecodedBytes(
        typeOid: 999999,
        isBinary: false,
        bytes: Uint8List.fromList(utf8.encode('(1,2)')),
        encoding: utf8,
      );
      expect(_text(v), '(1,2)');
    });

    test('the grid cell text goes through the same path', () {
      expect(
        postgresResultCellToDisplayString(_binary(790, _i64(100)), typeOid: 790),
        r'$1.00',
      );
    });
  });

  group('driver objects print as PostgreSQL does', () {
    test('interval and time', () {
      expect(
        postgresDriverValueText(
            Interval(months: 14, days: 3, microseconds: 14706000000)),
        '1 year 2 mons 3 days 04:05:06',
      );
      expect(postgresDriverValueText(Interval()), '00:00:00');
      expect(postgresDriverValueText(Time(10, 30, 15, 250)), '10:30:15.25');
    });

    test('geometric types', () {
      expect(postgresDriverValueText(const Point(10.5, 20.3)), '(10.5,20.3)');
      expect(postgresDriverValueText(const Point(10, 0)), '(10,0)');
      expect(postgresDriverValueText(Circle(const Point(5, 5), 10)),
          '<(5,5),10>');
      expect(
        postgresDriverValueText(
            LineSegment(const Point(0, 0), const Point(10, 10))),
        '[(0,0),(10,10)]',
      );
      expect(
        postgresDriverValueText(Path(
            const [Point(0, 0), Point(10, 0), Point(10, 10)],
            open: false)),
        '((0,0),(10,0),(10,10))',
      );
      expect(
        postgresDriverValueText(Path(const [Point(0, 0), Point(1, 1)], open: true)),
        '[(0,0),(1,1)]',
      );
      expect(postgresDriverValueText(Line(1, -1, 0)), '{1,-1,0}');
    });

    test('ranges', () {
      expect(
        postgresDriverValueText(
            IntRange(1, 100, Bounds(Bound.inclusive, Bound.exclusive))),
        '[1,100)',
      );
      expect(postgresDriverValueText(IntRange.empty()), 'empty');
      expect(
        postgresDriverValueText(DateRange(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 6, 30),
          Bounds(Bound.inclusive, Bound.exclusive),
        )),
        '[2026-01-01,2026-06-30)',
      );
    });

    test('plain values are not claimed', () {
      expect(postgresDriverValueText('text'), isNull);
      expect(postgresDriverValueText(42), isNull);
    });
  });
}
