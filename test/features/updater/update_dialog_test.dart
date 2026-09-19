import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/updater/sha256_checksums.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/updater/update_changelog_view.dart';
import 'package:querya_desktop/features/updater/update_controller.dart';
import 'package:querya_desktop/features/updater/update_dialog.dart';

import '../../support/querya_theme_test_shell.dart';

const _asset = UpdateAsset(
  name: 'Querya-Desktop-0.5.1-linux.zip',
  downloadUrl: 'https://example.com/querya.zip',
  sizeBytes: 10,
);

const _manifest = UpdateManifest(
  version: '0.5.1',
  changelog: 'Integrity and packaging fixes.',
  assets: [_asset],
);

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

  group('UpdateDialogContent', () {
    var clipboardContent = '';

    setUp(() {
      clipboardContent = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardContent = (call.arguments as Map)['text'] as String;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardContent};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('Download label is not Download & Install', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const SizedBox(
            width: 800,
            height: 700,
            child: UpdateDialogContent(
              initialManifest: _manifest,
              isInstallBlocked: false,
              hasUnsavedWork: _noUnsaved,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Download & Install'), findsNothing);
    });

    testWidgets('SHA256 mismatch shows an error instead of hanging',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: SizedBox(
            width: 800,
            height: 700,
            child: UpdateDialogContent(
              initialManifest: _manifest,
              isInstallBlocked: false,
              hasUnsavedWork: _noUnsaved,
              selectAsset: (_) => _asset,
              download: (_, __) async {
                throw const UpdateChecksumMismatchException(
                  fileName: 'querya.zip',
                  expected: 'aa',
                  actual: 'bb',
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('SHA256 mismatch'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('snap/flatpak offers copy command and does not download',
        (tester) async {
      var downloaded = false;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: SizedBox(
            width: 800,
            height: 700,
            child: UpdateDialogContent(
              initialManifest: _manifest,
              isInstallBlocked: true,
              packageUpdateCommand: 'snap refresh',
              showCopyToast: false,
              hasUnsavedWork: _noUnsaved,
              download: (_, __) async {
                downloaded = true;
                return File('/tmp/should-not-download.zip');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Download'), findsNothing);
      expect(find.text('Copy update command'), findsOneWidget);

      await tester.tap(find.text('Copy update command'));
      await tester.pump();

      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clip?.text, 'snap refresh');
      expect(downloaded, isFalse);
    });

    testWidgets('dirty restart cancel does not install', (tester) async {
      var installed = false;
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: SizedBox(
            width: 800,
            height: 700,
            child: UpdateDialogContent(
              initialManifest: _manifest,
              isInstallBlocked: false,
              hasUnsavedWork: () => true,
              selectAsset: (_) => _asset,
              download: (_, __) async => File('/tmp/querya-update.zip'),
              install: (_) async => installed = true,
              confirmRestartIfUnsaved: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Restart & Update Now'), findsOneWidget);
      await tester.tap(find.text('Restart & Update Now'));
      await tester.pump();
      expect(installed, isFalse);
    });
  });
}

bool _noUnsaved() => false;
