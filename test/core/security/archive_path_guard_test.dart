import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/archive_path_guard.dart';

void main() {
  group('isArchiveExtractPathWithinRoot', () {
    test('allows paths inside root', () {
      expect(
        isArchiveExtractPathWithinRoot('/tmp/ext', '/tmp/ext/file.txt'),
        isTrue,
      );
    });

    test('allows root path itself', () {
      expect(
        isArchiveExtractPathWithinRoot('/tmp/ext', '/tmp/ext'),
        isTrue,
      );
    });

    test('rejects sibling prefix paths (startsWith false positive)', () {
      expect(
        isArchiveExtractPathWithinRoot('/tmp/abc', '/tmp/abcd/evil.txt'),
        isFalse,
      );
    });

    test('rejects paths outside root', () {
      expect(
        isArchiveExtractPathWithinRoot('/tmp/ext', '/tmp/other/file.txt'),
        isFalse,
      );
    });
  });

  group('isArchiveEntryNameSafe', () {
    test('rejects traversal and absolute names', () {
      expect(isArchiveEntryNameSafe('../evil.txt'), isFalse);
      expect(isArchiveEntryNameSafe('/etc/passwd'), isFalse);
      expect(isArchiveEntryNameSafe(r'\windows\system32'), isFalse);
    });

    test('allows relative safe names', () {
      expect(isArchiveEntryNameSafe('manifest.json'), isTrue);
      expect(isArchiveEntryNameSafe('bin/driver'), isTrue);
      expect(isArchiveEntryNameSafe('icons/icon.png'), isTrue);
      expect(isArchiveEntryNameSafe('src/control.dart'), isTrue);
      expect(isArchiveEntryNameSafe('lib/auxiliary.py'), isTrue);
      expect(isArchiveEntryNameSafe('data/printer.dart'), isTrue);
      expect(isArchiveEntryNameSafe('com10.txt'), isTrue);
      expect(isArchiveEntryNameSafe('null_safety.dart'), isTrue);
    });

    test('rejects empty entry names', () {
      expect(isArchiveEntryNameSafe(''), isFalse);
    });

    test('rejects Windows drive letters (#919)', () {
      expect(isArchiveEntryNameSafe(r'C:\Windows\System32\payload.dll'), isFalse);
      expect(isArchiveEntryNameSafe('C:/test.txt'), isFalse);
      expect(isArchiveEntryNameSafe(r'c:\test.txt'), isFalse);
      expect(isArchiveEntryNameSafe('D:file.exe'), isFalse);
      expect(isArchiveEntryNameSafe(r'sub/C:\test.txt'), isFalse);
      expect(isArchiveEntryNameSafe(r'sub\D:file.exe'), isFalse);
    });

    test('rejects Windows reserved device names and their extensions (#919)', () {
      final reserved = [
        'CON', 'con', 'CON.txt', 'con.json',
        'PRN', 'prn', 'PRN.dat', 'prn.txt',
        'AUX', 'aux', 'aux.h', 'AUX.tar.gz',
        'NUL', 'nul', 'nul.png', 'NUL.txt',
        'COM1', 'com1.txt', 'COM9', 'com9.exe',
        'LPT1', 'lpt1.txt', 'LPT9', 'lpt9.dat',
      ];
      for (final name in reserved) {
        expect(isArchiveEntryNameSafe(name), isFalse, reason: 'Expected $name to be rejected');
        expect(isArchiveEntryNameSafe('nested/$name'), isFalse, reason: 'Expected nested/$name to be rejected');
        expect(isArchiveEntryNameSafe('sub\\path\\$name'), isFalse, reason: 'Expected sub\\path\\$name to be rejected');
        expect(isArchiveEntryNameSafe('$name/file.txt'), isFalse, reason: 'Expected $name/file.txt to be rejected');
      }
    });

    test('rejects null bytes and control characters (#919)', () {
      expect(isArchiveEntryNameSafe('file\x00name.txt'), isFalse);
      expect(isArchiveEntryNameSafe('file\nname.txt'), isFalse);
      expect(isArchiveEntryNameSafe('file\rname.txt'), isFalse);
      expect(isArchiveEntryNameSafe('file\x1Bname.txt'), isFalse);
      expect(isArchiveEntryNameSafe('file\x7Fname.txt'), isFalse);
      expect(isArchiveEntryNameSafe('dir/\x00/evil.txt'), isFalse);
    });
  });
}
