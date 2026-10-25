/// A `pg_settings` value with its [unit] spelled out (#1822 run-through): the
/// raw `16384` of `shared_buffers` means 16384 blocks of 8 kB, so the card
/// shows `128 MB`. Values with an unknown or no unit come back as they are.
String formatPgSetting(String setting, String? unit) {
  final n = int.tryParse(setting);
  if (n == null || unit == null || unit.isEmpty) return setting;
  final bytes = switch (unit) {
    'B' => n,
    'kB' => n * 1024,
    '8kB' => n * 8 * 1024,
    'MB' => n * 1024 * 1024,
    'GB' => n * 1024 * 1024 * 1024,
    _ => null,
  };
  if (bytes == null) return '$setting $unit';
  const steps = [
    (1024 * 1024 * 1024 * 1024, 'TB'),
    (1024 * 1024 * 1024, 'GB'),
    (1024 * 1024, 'MB'),
    (1024, 'kB'),
  ];
  for (final (size, label) in steps) {
    if (bytes >= size) {
      final v = bytes / size;
      return '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)} $label';
    }
  }
  return '$bytes B';
}
