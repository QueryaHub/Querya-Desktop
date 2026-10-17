import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/installers/macos_sparkle_installer.dart';

void main() {
  group('parseCodesignTeamId (#1588)', () {
    test('reads the Team ID of a Developer ID signature', () {
      const out = 'Executable=/Applications/Querya.app/Contents/MacOS/querya\n'
          'Identifier=com.queryahub.querya\n'
          'Authority=Developer ID Application: QueryaHub (AB12CD34EF)\n'
          'TeamIdentifier=AB12CD34EF\n'
          'Sealed Resources version=2 rules=13 files=120\n';
      expect(parseCodesignTeamId(out), 'AB12CD34EF');
    });

    test('an ad-hoc signature has none', () {
      const out = 'Identifier=querya_desktop\n'
          'Signature=adhoc\n'
          'TeamIdentifier=not set\n';
      expect(parseCodesignTeamId(out), isNull);
    });

    test('no TeamIdentifier line has none', () {
      expect(parseCodesignTeamId('code object is not signed at all'), isNull);
      expect(parseCodesignTeamId(''), isNull);
    });
  });

  group('signerMismatchProblem (#1588)', () {
    test('the same team may replace the app', () {
      expect(
        signerMismatchProblem(installedTeam: 'AB12CD34EF', updateTeam: 'AB12CD34EF'),
        isNull,
      );
    });

    test('another team may not', () {
      expect(
        signerMismatchProblem(installedTeam: 'AB12CD34EF', updateTeam: 'ZZ99ZZ99ZZ'),
        allOf(contains('different developer'), contains('ZZ99ZZ99ZZ'),
            contains('AB12CD34EF')),
      );
    });

    test('an ad-hoc or unsigned update may not replace a signed app', () {
      expect(
        signerMismatchProblem(installedTeam: 'AB12CD34EF', updateTeam: null),
        contains('not signed by the developer'),
      );
    });

    test('an unsigned installed app has nothing to compare with', () {
      expect(signerMismatchProblem(installedTeam: null, updateTeam: null), isNull);
      expect(
        signerMismatchProblem(installedTeam: null, updateTeam: 'AB12CD34EF'),
        isNull,
      );
    });
  });
}
