/// Converts SQL result cells to display strings without a second isolate copy.
///
/// Prefer this over [compute] for large matrices: shipping `List<List<Object?>>`
/// across isolates often costs more than `toString()` itself and roughly
/// doubles peak memory. Yielding every [yieldEvery] rows keeps the UI isolate
/// responsive for 10k+ row caps.
library;

const int kResultStringConvertYieldEvery = 250;

/// Maps null cells to `'NULL'` and others via [Object.toString].
String resultCellToDisplayString(Object? value) =>
    value == null ? 'NULL' : value.toString();

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
