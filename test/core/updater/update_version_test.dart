import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/update_version.dart';

void main() {
  group('UpdateVersion.tryParse', () {
    test('parses stable semver and strips leading v', () {
      expect(UpdateVersion.tryParse('v0.5.0')?.toString(), '0.5.0');
      expect(UpdateVersion.tryParse('1.2.3')?.isPreRelease, isFalse);
    });

    test('parses pre-release suffix', () {
      final version = UpdateVersion.tryParse('0.5.0-beta.1');
      expect(version?.isPreRelease, isTrue);
      expect(version?.preRelease, 'beta.1');
    });

    test('returns null for invalid tags', () {
      expect(UpdateVersion.tryParse(''), isNull);
      expect(UpdateVersion.tryParse('not-a-version'), isNull);
      expect(UpdateVersion.tryParse('1.2'), isNull);
    });
  });

  group('UpdateVersion.compareTo', () {
    test('orders core versions numerically', () {
      final a = UpdateVersion.tryParse('0.4.9')!;
      final b = UpdateVersion.tryParse('0.5.0')!;
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
    });

    test('stable release is newer than same core pre-release', () {
      final stable = UpdateVersion.tryParse('1.0.0')!;
      final beta = UpdateVersion.tryParse('1.0.0-beta.1')!;
      expect(stable.compareTo(beta), greaterThan(0));
      expect(beta.compareTo(stable), lessThan(0));
    });
  });

  group('UpdateVersion.isUpdateAvailable', () {
    test('detects newer stable version', () {
      final current = UpdateVersion.tryParse('0.4.9')!;
      final candidate = UpdateVersion.tryParse('0.5.0')!;
      expect(
        UpdateVersion.isUpdateAvailable(
          current: current,
          candidate: candidate,
          allowPreRelease: false,
        ),
        isTrue,
      );
    });

    test('ignores pre-release on stable channel', () {
      final current = UpdateVersion.tryParse('0.4.9')!;
      final candidate = UpdateVersion.tryParse('0.5.0-beta.1')!;
      expect(
        UpdateVersion.isUpdateAvailable(
          current: current,
          candidate: candidate,
          allowPreRelease: false,
        ),
        isFalse,
      );
    });

    test('allows pre-release on dev channel', () {
      final current = UpdateVersion.tryParse('0.4.9')!;
      final candidate = UpdateVersion.tryParse('0.5.0-beta.1')!;
      expect(
        UpdateVersion.isUpdateAvailable(
          current: current,
          candidate: candidate,
          allowPreRelease: true,
        ),
        isTrue,
      );
    });

    test('returns false when already up to date', () {
      final current = UpdateVersion.tryParse('0.5.0')!;
      expect(
        UpdateVersion.isUpdateAvailable(
          current: current,
          candidate: current,
          allowPreRelease: true,
        ),
        isFalse,
      );
    });
  });
}
