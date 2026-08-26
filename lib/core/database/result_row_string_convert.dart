import 'package:flutter/foundation.dart';

const int kResultStringConvertYieldEvery = 250;
const int kResultStringConvertComputeThreshold = 1000;

/// High-performance string interning pool for deduplicating cell strings
/// across low-cardinality database columns (e.g. booleans, enums, status codes, IDs).
class StringInternPool {
  StringInternPool({
    this.maxEntries = 4096,
    this.maxStringLength = 128,
  }) {
    _pool.addAll(_preloaded);
  }

  final int maxEntries;
  final int maxStringLength;

  static const Map<String, String> _preloaded = {
    'NULL': 'NULL',
    'true': 'true',
    'false': 'false',
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
    '10': '10',
    '': '',
    'active': 'active',
    'inactive': 'inactive',
    'pending': 'pending',
    'completed': 'completed',
    'success': 'success',
    'failed': 'failed',
    'error': 'error',
    'warning': 'warning',
    'info': 'info',
    'deleted': 'deleted',
    'draft': 'draft',
    'published': 'published',
  };

  final Map<String, String> _pool = {};

  int get size => _pool.length;

  /// Returns the canonical deduplicated instance of [value].
  String intern(String value) {
    if (value.length > maxStringLength) {
      return value;
    }
    final existing = _pool[value];
    if (existing != null) return existing;

    if (_pool.length < maxEntries) {
      _pool[value] = value;
    }
    return value;
  }

  /// Converts [value] to string and returns the interned canonical instance.
  String internObject(Object? value) {
    if (value == null) return 'NULL';
    if (value is String) return intern(value);
    if (value is bool) return value ? 'true' : 'false';
    if (value is int && value >= 0 && value <= 10) {
      return _preloaded[value.toString()] ?? value.toString();
    }
    return intern(value.toString());
  }
}

/// Maps null cells to `'NULL'` and others via [Object.toString].
String resultCellToDisplayString(Object? value, [StringInternPool? pool]) {
  if (pool != null) {
    return pool.internObject(value);
  }
  if (value == null) return 'NULL';
  if (value is bool) return value ? 'true' : 'false';
  return value.toString();
}

/// Converts [rowValues] to string rows synchronously using a string interning pool.
List<List<String>> convertResultRowsToStringsSync(
  List<List<Object?>> rowValues, {
  StringInternPool? pool,
}) {
  if (rowValues.isEmpty) return const [];
  final activePool = pool ?? StringInternPool();
  return [
    for (final row in rowValues)
      [for (final value in row) activePool.internObject(value)],
  ];
}

/// Top-level function suitable for [compute] offloading.
List<List<String>> convertResultRowsToStringsCompute(List<List<Object?>> rowValues) =>
    convertResultRowsToStringsSync(rowValues);

/// Converts [rowValues] to string rows, yielding periodically and interning strings.
Future<List<List<String>>> convertResultRowsToStringsYielding(
  List<List<Object?>> rowValues, {
  int yieldEvery = kResultStringConvertYieldEvery,
  StringInternPool? pool,
}) async {
  if (rowValues.isEmpty) return const [];

  final activePool = pool ?? StringInternPool();
  final out = <List<String>>[];
  for (var i = 0; i < rowValues.length; i++) {
    final row = rowValues[i];
    out.add([
      for (final value in row) activePool.internObject(value),
    ]);
    if (yieldEvery > 0 && (i + 1) % yieldEvery == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}

/// Converts [rowValues] adaptively: offloads to a background isolate via [compute]
/// if row count >= [computeThreshold], otherwise yields on the main isolate.
Future<List<List<String>>> convertResultRowsToStringsAdaptive(
  List<List<Object?>> rowValues, {
  int computeThreshold = kResultStringConvertComputeThreshold,
  int yieldEvery = kResultStringConvertYieldEvery,
  StringInternPool? pool,
}) async {
  if (rowValues.isEmpty) return const [];
  if (rowValues.length >= computeThreshold) {
    return compute(convertResultRowsToStringsCompute, rowValues);
  }
  return convertResultRowsToStringsYielding(
    rowValues,
    yieldEvery: yieldEvery,
    pool: pool,
  );
}
