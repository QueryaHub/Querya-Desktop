import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

/// Text for the values the PostgreSQL driver hands over that are not plain
/// Dart values, in the form PostgreSQL itself prints them (`[1,100)`,
/// `(10.5,20.3)`, `1 year 2 mons`), so a cell reads and edits like psql shows
/// it. Null when [value] is not one of these.
String? postgresDriverValueText(Object value) {
  if (value is Point) return _point(value);
  if (value is Line) return '{${_n(value.a)},${_n(value.b)},${_n(value.c)}}';
  if (value is LineSegment) {
    return '[${_point(value.p1)},${_point(value.p2)}]';
  }
  if (value is Box) return '${_point(value.p1)},${_point(value.p2)}';
  if (value is Path) {
    final pts = value.points.map(_point).join(',');
    return value.open ? '[$pts]' : '($pts)';
  }
  if (value is Polygon) return '(${value.points.map(_point).join(',')})';
  if (value is Circle) return '<${_point(value.center)},${_n(value.radius)}>';
  if (value is Interval) return _interval(value);
  if (value is Time) return _clock(value.microseconds);
  if (value is Range) return _range(value);
  return null;
}

/// Text for bytes the driver left undecoded. Never throws: a type this does
/// not know shows as UTF-8 when the bytes are text, else as `\x` hex.
String postgresUndecodedText(UndecodedBytes value) {
  if (!value.isBinary) {
    return utf8.decode(value.bytes, allowMalformed: true);
  }
  try {
    final scalar = _scalar(value.typeOid, value.bytes);
    if (scalar != null) return scalar;
    final record = _record(value.bytes);
    if (record != null) return record;
  } catch (_) {
    // Fall through to the plain forms.
  }
  return _textOrHex(value.bytes);
}

String _textOrHex(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes);
    final printable = !text.codeUnits.any((c) => c < 0x09 || (c > 0x0d && c < 0x20));
    if (printable) return text;
  } catch (_) {}
  return _hex(bytes);
}

String _hex(Uint8List bytes) {
  final out = StringBuffer(r'\x');
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

// -- driver objects ---------------------------------------------------------

String _n(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

String _point(Point p) => '(${_n(p.latitude)},${_n(p.longitude)})';

String _two(int v) => v.toString().padLeft(2, '0');

String _clock(int micros) {
  final neg = micros < 0;
  var m = micros.abs();
  final h = m ~/ 3600000000;
  m %= 3600000000;
  final min = m ~/ 60000000;
  m %= 60000000;
  final s = m ~/ 1000000;
  final f = m % 1000000;
  final frac = f == 0 ? '' : '.${f.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${neg ? '-' : ''}${_two(h)}:${_two(min)}:${_two(s)}$frac';
}

String _interval(Interval i) {
  final parts = <String>[];
  final years = i.months ~/ 12;
  final mons = i.months.remainder(12);
  if (years != 0) parts.add('$years year${years.abs() == 1 ? '' : 's'}');
  if (mons != 0) parts.add('$mons mon${mons.abs() == 1 ? '' : 's'}');
  if (i.days != 0) parts.add('${i.days} day${i.days.abs() == 1 ? '' : 's'}');
  if (i.microseconds != 0 || parts.isEmpty) {
    parts.add(_clock(i.microseconds));
  }
  return parts.join(' ');
}

String _bound(Object? v) {
  if (v == null) return '';
  if (v is DateTime) {
    final iso = v.toIso8601String();
    return v.hour == 0 && v.minute == 0 && v.second == 0 && v.millisecond == 0
        ? iso.split('T').first
        : iso;
  }
  return '$v';
}

String _range(Range r) {
  final lower = r.lower;
  final upper = r.upper;
  if (lower != null && upper != null && lower == upper &&
      r.bounds.lower == Bound.inclusive && r.bounds.upper == Bound.exclusive) {
    return 'empty';
  }
  final lb = r.bounds.lower == Bound.inclusive ? '[' : '(';
  final ub = r.bounds.upper == Bound.inclusive ? ']' : ')';
  return '$lb${_bound(lower)},${_bound(upper)}$ub';
}

// -- binary values ----------------------------------------------------------

const _rangeElement = {
  3904: 23, // int4range
  3906: 1700, // numrange
  3908: 1114, // tsrange
  3910: 1184, // tstzrange
  3912: 1082, // daterange
  3926: 20, // int8range
};

const _multirangeElement = {
  4451: 23, // int4multirange
  4532: 1700, // nummultirange
  4533: 1114, // tsmultirange
  4534: 1184, // tstzmultirange
  4535: 1082, // datemultirange
  4536: 20, // int8multirange
};

String? _scalar(int oid, Uint8List b) {
  final d = ByteData.sublistView(b);
  switch (oid) {
    case 16:
      return b[0] != 0 ? 'true' : 'false';
    case 21:
      return d.getInt16(0).toString();
    case 23:
      return d.getInt32(0).toString();
    case 20:
      return d.getInt64(0).toString();
    case 26: // oid
    case 28: // xid
    case 29: // cid
      return d.getUint32(0).toString();
    case 700:
      return _float(d.getFloat32(0));
    case 701:
      return _float(d.getFloat64(0));
    case 1700:
      return _numeric(d);
    case 790:
      return _money(d.getInt64(0));
    case 1082:
      return _date(d.getInt32(0));
    case 1114:
      return _timestamp(d.getInt64(0), tz: false);
    case 1184:
      return _timestamp(d.getInt64(0), tz: true);
    case 1083:
      return _clock(d.getInt64(0));
    case 1266:
      return _timeTz(d);
    case 1186:
      return _interval(Interval(
        microseconds: d.getInt64(0),
        days: d.getInt32(8),
        months: d.getInt32(12),
      ));
    case 869:
      return _inet(b, cidr: false);
    case 650:
      return _inet(b, cidr: true);
    case 829:
    case 774:
      return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
    case 1560:
    case 1562:
      return _bits(d, b);
    case 2950:
      final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
          '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    case 25:
    case 1042:
    case 1043:
    case 19:
    case 114:
      return utf8.decode(b);
    case 3802: // jsonb: a version byte, then JSON text
      return utf8.decode(b.sublist(1));
    case 17:
      return _hex(b);
  }
  final rangeElement = _rangeElement[oid];
  if (rangeElement != null) return _rangeBytes(d, b, rangeElement);
  final multiElement = _multirangeElement[oid];
  if (multiElement != null) return _multirangeBytes(d, b, multiElement);
  return null;
}

String _float(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v < 0 ? '-Infinity' : 'Infinity';
  return _n(v);
}

String _numeric(ByteData d) {
  final nDigits = d.getInt16(0);
  final weight = d.getInt16(2);
  final sign = d.getUint16(4);
  final dScale = d.getInt16(6);
  if (sign == 0xC000) return 'NaN';
  if (sign == 0xD000) return 'Infinity';
  if (sign == 0xF000) return '-Infinity';
  int digit(int i) => i >= 0 && i < nDigits ? d.getInt16(8 + i * 2) : 0;

  final whole = StringBuffer();
  if (weight < 0) {
    whole.write('0');
  } else {
    for (var i = 0; i <= weight; i++) {
      final g = digit(i).toString();
      whole.write(i == 0 ? g : g.padLeft(4, '0'));
    }
  }
  var out = whole.toString().replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (dScale > 0) {
    final frac = StringBuffer();
    for (var k = 1; frac.length < dScale; k++) {
      frac.write(digit(weight + k).toString().padLeft(4, '0'));
    }
    out = '$out.${frac.toString().substring(0, dScale)}';
  }
  return sign == 0x4000 ? '-$out' : out;
}

String _money(int cents) {
  final neg = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${neg ? '-' : ''}\$$grouped.${(abs % 100).toString().padLeft(2, '0')}';
}

final _pgEpoch = DateTime.utc(2000);

String _date(int days) {
  if (days == 0x7fffffff) return 'infinity';
  if (days == -0x80000000) return '-infinity';
  final dt = _pgEpoch.add(Duration(days: days));
  return '${dt.year.toString().padLeft(4, '0')}-${_two(dt.month)}-${_two(dt.day)}';
}

String _timestamp(int micros, {required bool tz}) {
  if (micros == 0x7fffffffffffffff) return 'infinity';
  if (micros == -0x8000000000000000) return '-infinity';
  final dt = _pgEpoch.add(Duration(microseconds: micros));
  final f = dt.microsecond + dt.millisecond * 1000;
  final frac =
      f == 0 ? '' : '.${f.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${dt.year.toString().padLeft(4, '0')}-${_two(dt.month)}-${_two(dt.day)} '
      '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}$frac${tz ? '+00' : ''}';
}

String _timeTz(ByteData d) {
  final clock = _clock(d.getInt64(0));
  // PostgreSQL stores the zone as seconds WEST of UTC.
  final east = -d.getInt32(8);
  final sign = east < 0 ? '-' : '+';
  final abs = east.abs();
  final h = abs ~/ 3600;
  final m = (abs % 3600) ~/ 60;
  return '$clock$sign${_two(h)}${m == 0 ? '' : ':${_two(m)}'}';
}

String _inet(Uint8List b, {required bool cidr}) {
  final bits = b[1];
  final len = b[3];
  final addr = Uint8List.fromList(b.sublist(4, 4 + len));
  final text = InternetAddress.fromRawAddress(addr).address;
  final full = len == 4 ? 32 : 128;
  return cidr || bits != full ? '$text/$bits' : text;
}

String _bits(ByteData d, Uint8List b) {
  final n = d.getInt32(0);
  final out = StringBuffer();
  for (var i = 0; i < n; i++) {
    final byte = b[4 + (i >> 3)];
    out.write((byte >> (7 - (i & 7))) & 1);
  }
  return out.toString();
}

String _rangeBytes(ByteData d, Uint8List b, int elementOid) {
  final flags = b[0];
  if (flags & 0x01 != 0) return 'empty';
  var pos = 1;
  String element() {
    final len = d.getInt32(pos);
    pos += 4;
    final bytes = Uint8List.sublistView(b, pos, pos + len);
    pos += len;
    return _scalar(elementOid, bytes) ?? _hex(bytes);
  }

  final hasLower = flags & 0x08 == 0;
  final hasUpper = flags & 0x10 == 0;
  final lower = hasLower ? element() : '';
  final upper = hasUpper ? element() : '';
  final lb = flags & 0x02 != 0 ? '[' : '(';
  final ub = flags & 0x04 != 0 ? ']' : ')';
  return '$lb$lower,$upper$ub';
}

String _multirangeBytes(ByteData d, Uint8List b, int elementOid) {
  final n = d.getInt32(0);
  var pos = 4;
  final parts = <String>[];
  for (var i = 0; i < n; i++) {
    final len = d.getInt32(pos);
    pos += 4;
    final bytes = Uint8List.sublistView(b, pos, pos + len);
    pos += len;
    parts.add(_rangeBytes(ByteData.sublistView(bytes), bytes, elementOid));
  }
  return '{${parts.join(',')}}';
}

/// A composite value: `int32 columns`, then per column `oid, length, bytes`.
/// Accepted only when the bytes are consumed exactly, so unrelated binary
/// does not read as a record.
String? _record(Uint8List b) {
  if (b.length < 4) return null;
  final d = ByteData.sublistView(b);
  final n = d.getInt32(0);
  if (n < 0 || n > 1664) return null;
  var pos = 4;
  final cells = <String>[];
  for (var i = 0; i < n; i++) {
    if (pos + 8 > b.length) return null;
    final oid = d.getInt32(pos);
    final len = d.getInt32(pos + 4);
    pos += 8;
    if (oid <= 0) return null;
    if (len == -1) {
      cells.add('');
      continue;
    }
    if (len < 0 || pos + len > b.length) return null;
    final bytes = Uint8List.sublistView(b, pos, pos + len);
    pos += len;
    String text;
    try {
      text = _scalar(oid, bytes) ?? _record(bytes) ?? _textOrHex(bytes);
    } catch (_) {
      text = _textOrHex(bytes);
    }
    cells.add(_recordQuote(text));
  }
  if (pos != b.length) return null;
  return '(${cells.join(',')})';
}

String _recordQuote(String s) {
  if (s.isEmpty) return '""';
  if (!RegExp(r'[\s,()"\\]').hasMatch(s)) return s;
  return '"${s.replaceAll(r'\', r'\\').replaceAll('"', '""')}"';
}
