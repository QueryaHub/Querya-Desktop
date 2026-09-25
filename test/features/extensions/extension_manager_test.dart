import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/motion/querya_cross_fade_stack.dart';
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
      expect(find.text('Install from file…'), findsOneWidget);
      expect(find.byType(QueryaTabStrip), findsOneWidget);
      expect(find.byType(QueryaCrossFadeStack), findsOneWidget);

      // Switch to Marketplace tab
      await tester.tap(find.text('Marketplace'));
      await tester.pumpAndSettle();

      expect(find.text('ClickHouse Driver'), findsOneWidget);
      expect(find.textContaining('preview listings only'), findsOneWidget);
      expect(find.text('Preview'), findsWidgets);

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(
        find.text('All installed extensions are up to date!'),
        findsNothing,
      );
      expect(
        find.text('Extension update checks are not available yet'),
        findsOneWidget,
      );
      expect(find.textContaining('Marketplace API'), findsOneWidget);
    });

    group('marketplace search', () {
      Future<_ControlledMarketplace> openMarketplace(
        WidgetTester tester,
      ) async {
        final repo = _ControlledMarketplace();
        MarketplaceRepository.instance = repo;
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
        await tester.tap(find.text('Marketplace'));
        await tester.pumpAndSettle();
        repo.searches.clear();
        return repo;
      }

      testWidgets('debounces keystrokes into a single request', (tester) async {
        final repo = await openMarketplace(tester);
        final field = find.byType(TextField);

        for (final q in ['c', 'cl', 'cli', 'click']) {
          await tester.enterText(field, q);
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(repo.searches, isEmpty);

        await tester.pump(kMarketplaceSearchDebounce);
        expect(repo.searches, ['click']);
        repo.complete('click', [_manifest('click.ext', 'Click Result')]);
        await tester.pumpAndSettle();
        expect(find.text('Click Result'), findsOneWidget);
      });

      testWidgets('a stale response arriving late is ignored', (tester) async {
        final repo = await openMarketplace(tester);
        final field = find.byType(TextField);

        await tester.enterText(field, 'click');
        await tester.pump(kMarketplaceSearchDebounce);
        await tester.enterText(field, 'clickhouse');
        await tester.pump(kMarketplaceSearchDebounce);
        expect(repo.searches, ['click', 'clickhouse']);

        // Newer response first, older one afterwards.
        repo.complete('clickhouse', [_manifest('ch.ext', 'ClickHouse Result')]);
        await tester.pumpAndSettle();
        repo.complete('click', [_manifest('c.ext', 'Stale Result')]);
        await tester.pumpAndSettle();

        expect(find.text('ClickHouse Result'), findsOneWidget);
        expect(find.text('Stale Result'), findsNothing);
      });

      testWidgets('closing the dialog while a search is in flight is safe',
          (tester) async {
        final repo = await openMarketplace(tester);

        await tester.enterText(find.byType(TextField), 'click');
        await tester.pump(kMarketplaceSearchDebounce);
        expect(repo.searches, ['click']);

        // Dispose the dialog, then let the request finish.
        await tester.pumpWidget(const material.SizedBox());
        repo.complete('click', [_manifest('c.ext', 'Late Result')]);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('typing then closing before the debounce fires sends nothing',
          (tester) async {
        final repo = await openMarketplace(tester);

        await tester.enterText(find.byType(TextField), 'click');
        await tester.pumpWidget(const material.SizedBox());
        await tester.pump(kMarketplaceSearchDebounce * 2);

        expect(repo.searches, isEmpty);
      });
    });
  });
}

ExtensionManifest _manifest(String id, String name) => ExtensionManifest(
      id: id,
      name: name,
      version: '1.0.0',
      publisher: 'QueryaHub',
      type: ExtensionType.databaseDriver,
      engines: const {'querya_desktop': '^0.4.7'},
    );

/// Marketplace whose `search` futures complete only when the test says so.
class _ControlledMarketplace extends MockMarketplaceRepository {
  final List<String> searches = [];
  final Map<String, Completer<List<ExtensionManifest>>> _pending = {};

  @override
  Future<List<ExtensionManifest>> search(String query, {ExtensionType? type}) {
    searches.add(query);
    return (_pending[query] = Completer<List<ExtensionManifest>>()).future;
  }

  void complete(String query, List<ExtensionManifest> result) =>
      _pending[query]!.complete(result);
}
