import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/extensions/extension_command_sync.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

void main() {
  final registry = QueryaCommandRegistry.instance;
  final sync = ExtensionCommandSync.instance;

  setUp(() {
    registry.resetForTest();
    sync.resetForTest();
  });

  tearDown(() {
    sync.resetForTest();
    registry.resetForTest();
  });

  ExtensionManifest clickhouse() {
    return const ExtensionManifest(
      id: 'queryahub.clickhouse-driver',
      name: 'ClickHouse Driver',
      version: '1.0.0',
      publisher: 'QueryaHub',
      type: ExtensionType.databaseDriver,
      engines: {'querya_desktop': '^0.5.0'},
      contributions: ExtensionContributions(
        commands: [
          CommandContribution(
            id: 'ext.clickhouse.cluster_status',
            title: 'ClickHouse: Show Cluster Status',
            category: 'ClickHouse',
          ),
        ],
      ),
    );
  }

  test('sync registers contributed commands in the palette registry', () {
    sync.sync([clickhouse()]);
    expect(
      registry['ext.clickhouse.cluster_status']?.title,
      'ClickHouse: Show Cluster Status',
    );
    expect(
      registry['ext.clickhouse.cluster_status']?.sourceExtensionId,
      'queryahub.clickhouse-driver',
    );
    expect(
      registry.search('cluster').map((c) => c.id),
      contains('ext.clickhouse.cluster_status'),
    );
  });

  test('removing a manifest unregisters its commands', () {
    sync.sync([clickhouse()]);
    expect(registry['ext.clickhouse.cluster_status'], isNotNull);

    sync.sync(const []);
    expect(registry['ext.clickhouse.cluster_status'], isNull);
  });

  test('disabling an extension drops its commands; enabling restores them', () {
    sync.sync([clickhouse()]);
    expect(registry['ext.clickhouse.cluster_status'], isNotNull);

    sync.setEnabled('queryahub.clickhouse-driver', false);
    expect(registry['ext.clickhouse.cluster_status'], isNull);

    sync.setEnabled('queryahub.clickhouse-driver', true);
    expect(registry['ext.clickhouse.cluster_status'], isNotNull);
  });

  testWidgets('execute forwards to invokeOverride (PluginRpcBridge path)',
      (tester) async {
    var ran = 0;
    sync.invokeOverride = (manifest, command, _) async {
      expect(manifest.id, 'queryahub.clickhouse-driver');
      expect(command.id, 'ext.clickhouse.cluster_status');
      ran++;
    };
    sync.sync([clickhouse()]);

    await tester.pumpWidget(
      const MaterialApp(home: SizedBox.shrink()),
    );
    final context = tester.element(find.byType(SizedBox));
    registry['ext.clickhouse.cluster_status']!.execute(context);
    await tester.pump();
    expect(ran, 1);
  });

  test('skips querya.* and ids without ext. prefix', () {
    registry.ensureCoreDefaults();
    sync.sync([
      const ExtensionManifest(
        id: 'evil.driver',
        name: 'Evil',
        version: '1.0.0',
        publisher: 'x',
        type: ExtensionType.databaseDriver,
        engines: {'querya_desktop': '^0.5.0'},
        contributions: ExtensionContributions(
          commands: [
            CommandContribution(
              id: 'querya.sql.execute',
              title: 'Hijack Execute',
            ),
            CommandContribution(
              id: 'cluster.status',
              title: 'No prefix',
            ),
            CommandContribution(
              id: 'ext.evil.ok',
              title: 'Allowed',
            ),
          ],
        ),
      ),
    ]);

    expect(registry['querya.sql.execute']?.sourceExtensionId, isNull);
    expect(registry['querya.sql.execute']?.title, isNot('Hijack Execute'));
    expect(registry['cluster.status'], isNull);
    expect(registry['ext.evil.ok']?.title, 'Allowed');
  });

  test('sync restores a core command if it was removed', () {
    registry.ensureCoreDefaults();
    registry.unregister('querya.sql.execute');
    expect(registry['querya.sql.execute'], isNull);

    sync.sync(const []);
    expect(registry['querya.sql.execute'], isNotNull);
    expect(registry['querya.sql.execute']?.sourceExtensionId, isNull);
  });

  testWidgets('RPC failure from invokeOverride toasts instead of hanging',
      (tester) async {
    final toasts = <String>[];
    sync.toastOverride = toasts.add;
    sync.invokeOverride = (_, __, ___) async {
      throw StateError('commands.execute is not available');
    };
    sync.sync([clickhouse()]);

    await tester.pumpWidget(
      const MaterialApp(home: SizedBox.shrink()),
    );
    final context = tester.element(find.byType(SizedBox));
    registry['ext.clickhouse.cluster_status']!.execute(context);
    await tester.pump();

    expect(toasts, hasLength(1));
    expect(toasts.single, contains('ClickHouse: Show Cluster Status'));
  });
}
