import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/local_extension_installer.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/platform/macos_sandbox.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/settings/preferences_extensions_section.dart';

import '../../support/querya_theme_test_shell.dart';

class _FakeLocalExtensionInstaller extends LocalExtensionInstaller {
  _FakeLocalExtensionInstaller({
    this.manifestToReturn,
    this.exceptionToThrow,
  });

  final ExtensionManifest? manifestToReturn;
  final Exception? exceptionToThrow;

  @override
  Future<ExtensionManifest> installFromPath(
    String path, {
    String? expectedSha256,
    void Function(double progress)? onProgress,
  }) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return manifestToReturn!;
  }
}

void main() {
  group('PreferencesExtensionsSection', () {
    testWidgets('renders section title, hint and action buttons', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: PreferencesExtensionsSection(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Install from file…'), findsOneWidget);
      expect(find.text('Open extensions folder'), findsOneWidget);
    });

    testWidgets('says extensions cannot run in the macOS sandbox (#1593)',
        (tester) async {
      MacOsSandbox.debugOverride = true;
      addTearDown(() => MacOsSandbox.debugOverride = null);
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(body: PreferencesExtensionsSection()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const material.ValueKey('extensions_sandbox_notice')),
        findsOneWidget,
      );
    });

    testWidgets('outside the sandbox there is no notice', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(body: PreferencesExtensionsSection()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const material.ValueKey('extensions_sandbox_notice')),
        findsNothing,
      );
    });

    testWidgets('renders installation error with wb.destructive and error icon (#1651)',
        (tester) async {
      final installer = _FakeLocalExtensionInstaller(
        exceptionToThrow: MarketplaceException('Corrupt zip archive.'),
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.darkDefault,
          child: material.Scaffold(
            body: PreferencesExtensionsSection(
              installer: installer,
              filePicker: () async => XFile('sample.zip'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install from file…'));
      await tester.pumpAndSettle();

      expect(find.text('Corrupt zip archive.'), findsOneWidget);
      final errorText = tester.widget<material.Text>(find.text('Corrupt zip archive.'));
      expect(
        errorText.style?.color,
        QueryaTheme.darkDefault.workbench.destructive,
      );

      final errorIcon = tester.widget<material.Icon>(
        find.byIcon(material.Icons.error_outline_rounded),
      );
      expect(
        errorIcon.color,
        QueryaTheme.darkDefault.workbench.destructive,
      );
    });

    testWidgets(
        'renders installation success with wb.success and checkmark icon (#1651)',
        (tester) async {
      const manifest = ExtensionManifest(
        id: 'corp.clickhouse',
        name: 'ClickHouse Driver',
        version: '1.2.0',
        publisher: 'Corp',
        type: ExtensionType.databaseDriver,
        engines: {'querya': '^1.0.0'},
      );
      final installer = _FakeLocalExtensionInstaller(
        manifestToReturn: manifest,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          data: QueryaTheme.lightDefault,
          child: material.Scaffold(
            body: PreferencesExtensionsSection(
              installer: installer,
              filePicker: () async => XFile('clickhouse.qext'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install from file…'));
      await tester.pumpAndSettle();

      const expectedMsg = 'Installed "ClickHouse Driver" (corp.clickhouse) v1.2.0.';
      expect(find.text(expectedMsg), findsOneWidget);

      final successText = tester.widget<material.Text>(find.text(expectedMsg));
      expect(
        successText.style?.color,
        QueryaTheme.lightDefault.workbench.success,
      );

      final successIcon = tester.widget<material.Icon>(
        find.byIcon(material.Icons.check_circle_outline_rounded),
      );
      expect(
        successIcon.color,
        QueryaTheme.lightDefault.workbench.success,
      );
    });
  });
}
