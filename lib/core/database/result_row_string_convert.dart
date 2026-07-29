import 'package:flutter/foundation.dart';

const int kResultStringConvertYieldEvery = 250;
const int kResultStringConvertComputeThreshold = 1000;

/// Maps null cells to `'NULL'` and others via [Object.toString].
String resultCellToDisplayString(Object? value) =>
    value == null ? 'NULL' : value.toString();

/// Converts [rowValues] to string rows synchronously.
List<List<String>> convertResultRowsToStringsSync(List<List<Object?>> rowValues) {
  if (rowValues.isEmpty) return const [];
  return [
    for (final row in rowValues)
      [for (final value in row) resultCellToDisplayString(value)],
  ];
}

/// Top-level function suitable for [compute] offloading.
List<List<String>> convertResultRowsToStringsCompute(List<List<Object?>> rowValues) =>
    convertResultRowsToStringsSync(rowValues);

/// Converts [rowValues] to string rows, yielding periodically.
Future<List<List<String>>> convertResultRowsToStringsYielding(
  List<List<Object?>> rowValues, {
  int yieldEvery = kResultStringConvertYieldEvery,
}) async {
  if (rowValues.isEmpty) return const [];

  final out = <List<String>>[];
  for (var i = 0; i < rowValues.length; i++) {
    final row = rowValues[i];
    out.add([
      for (final value in row) resultCellToDisplayString(value),
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
}) async {
  if (rowValues.isEmpty) return const [];
  if (rowValues.length >= computeThreshold) {
    return compute(convertResultRowsToStringsCompute, rowValues);
  }
  return convertResultRowsToStringsYielding(rowValues, yieldEvery: yieldEvery);
}
