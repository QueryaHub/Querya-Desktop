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
    });
  });
}
