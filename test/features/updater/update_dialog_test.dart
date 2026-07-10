import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/updater/update_changelog_view.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('UpdateChangelogView', () {
    testWidgets('renders markdown headings and bullet lists', (tester) async {
      const markdown = '''
## Release 0.5.0
- Faster CSV export
- SSL certificate UI
''';

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const UpdateChangelogView(markdown: markdown),
        ),
      );

      expect(find.text('Release 0.5.0'), findsOneWidget);
      expect(find.textContaining('Faster CSV export'), findsOneWidget);
      expect(find.textContaining('SSL certificate UI'), findsOneWidget);
    });

    testWidgets('shows fallback when changelog is empty', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const UpdateChangelogView(markdown: '   '),
        ),
      );

      expect(find.text('No release notes provided.'), findsOneWidget);
    });
  });

  group('UpdateController', () {
    test('showBadge reflects pending update', () {
      final controller = UpdateController();
      controller.resetForTest();
      expect(controller.showBadge, isFalse);

      controller.setPendingUpdate(
        const UpdateManifest(
          version: '0.5.0',
          changelog: '',
          assets: [],
        ),
      );
      expect(controller.showBadge, isTrue);

      controller.setDismissedVersionForTest('0.5.0');
      expect(controller.showBadge, isFalse);
    });
  });
}
