import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/postgresql/pg_setting_format.dart';

void main() {
  test('block and kilobyte settings are shown as sizes', () {
    expect(formatPgSetting('16384', '8kB'), '128 MB');
    expect(formatPgSetting('524288', '8kB'), '4 GB');
    expect(formatPgSetting('4096', 'kB'), '4 MB');
    expect(formatPgSetting('64', 'kB'), '64 kB');
    expect(formatPgSetting('1536', 'kB'), '1.5 MB');
  });

  test('no unit or a non-number stays as it is', () {
    expect(formatPgSetting('100', null), '100');
    expect(formatPgSetting('100', ''), '100');
    expect(formatPgSetting('Etc/UTC', null), 'Etc/UTC');
  });

  test('a unit that is not memory is kept next to the value', () {
    expect(formatPgSetting('5000', 'ms'), '5000 ms');
  });
}
