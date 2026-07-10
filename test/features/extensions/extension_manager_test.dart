import 'dart:io';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/features/extensions/presentation/pages/extension_manager_dialog.dart';
import 'package:querya_desktop/features/extensions/presentation/widgets/extension_card.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('ExtensionCard', () {
    testWidgets('renders manifest details and tag badges', (tester) async {
      const manifest = ExtensionManifest(
        id: 'queryahub.clickhouse-driver',
        name: 'ClickHouse Driver',
        version: '1.0.0',
        publisher: 'QueryaHub',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '^0.4.7'},
        description: 'Full support for ClickHouse databases.',
        tags: ['database', 'clickhouse', 'olap'],
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ExtensionCard(
              manifest: manifest,
              isInstalled: false,
            ),
          ),
        ),
      );

      expect(find.text('ClickHouse Driver'), findsOneWidget);
      expect(find.text('QueryaHub'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.text('Full support for ClickHouse databases.'), findsOneWidget);
      expect(find.text('clickhouse'), findsOneWidget);
      expect(find.text('Preview'), findsNWidgets(2));
      expect(find.text('Install'), findsNothing);
    });

    testWidgets('renders progress bar when isInstalling is true', (tester) async {
      const manifest = ExtensionManifest(
        id: 'queryahub.clickhouse-driver',
        name: 'ClickHouse Driver',
        version: '1.0.0',
        publisher: 'QueryaHub',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '^0.4.7'},
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Scaffold(
            body: ExtensionCard(
              manifest: manifest,
              isInstalled: false,
              isInstalling: true,
              installProgress: 0.45,
            ),
          ),
        ),
      );

      expect(find.byType(material.LinearProgressIndicator), findsOneWidget);
      expect(find.text('Installing 45%'), findsOneWidget);
    });
  });

  group('ExtensionManagerDialog', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('querya_ui_test_');
      ExtensionPaths.mockExtensionsDirectory = tempDir;
      await LocalExtensionRegistry.instance.reload();
      MarketplaceRepository.instance = MockMarketplaceRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      ExtensionPaths.mockExtensionsDirectory = null;
    });

    testWidgets('renders tabs and loads Marketplace items', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (ctx) => material.Scaffold(
              body: material.Center(
                child: PrimaryButton(
                  onPressed: () => showExtensionManagerDialog(ctx),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Installed (0)'), findsOneWidget);
      expect(find.text('Marketplace'), findsOneWidget);

      // Switch to Marketplace tab
      await tester.tap(find.text('Marketplace'));
      await tester.pumpAndSettle();

      expect(find.text('ClickHouse Driver'), findsOneWidget);
      expect(find.textContaining('preview listings only'), findsOneWidget);
      expect(find.text('Preview'), findsWidgets);
    });
  });
}
