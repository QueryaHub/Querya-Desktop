import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/extensions/extension_command_sync.dart';
import 'package:querya_desktop/core/extensions/extension_command_target.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;
  @override
  Future<String?> getTemporaryPath() async => _root;
  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
  @override
  Future<String?> getApplicationCachePath() async => _root;
  @override
  Future<String?> getLibraryPath() async => _root;
  @override
  Future<String?> getExternalStoragePath() async => _root;
  @override
  Future<List<String>?> getExternalCachePaths() async => [_root];
  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [_root];
  @override
  Future<String?> getDownloadsPath() async => _root;
}

/// #892: when multiple live connections exist for the same extension and
/// none is preferred, the command must go through a connection picker
/// instead of silently running against whichever session happened to
/// resolve first (or, worse, doing nothing but toast).
///
/// The live-session lookup itself needs a real driver process to populate,
/// so these tests use [ExtensionCommandSync.targetOverride] /
/// [ExtensionCommandSync.liveConnectionIdsOverride] to force the exact
/// "ambiguous" scenario deterministically, and verify the real (non-test)
/// candidate-resolution and picker-invocation code in
/// [ExtensionCommandSync] runs against real [ConnectionRow]s from [LocalDb].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int connDevId;
  late int connProdId;

  final registry = QueryaCommandRegistry.instance;
  final sync = ExtensionCommandSync.instance;

  const manifest = ExtensionManifest(
    id: 'queryahub.clickhouse-driver',
    name: 'ClickHouse',
    version: '1.0.0',
    publisher: 'QueryaHub',
    type: ExtensionType.databaseDriver,
    engines: {'querya_desktop': '^0.5.0'},
    contributions: ExtensionContributions(
      commands: [
        CommandContribution(
          id: 'ext.clickhouse.optimize_partition',
          title: 'Optimize Partition',
          category: 'ClickHouse',
        ),
      ],
    ),
  );

  setUpAll(() async {
    sqfliteFfiInit();
    tempDir =
        await Directory.systemTemp.createTemp('querya_ext_ambiguous_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();

    connDevId = await LocalDb.instance.addConnection(
      const ConnectionRow(
        type: 'clickhouse',
        name: 'ClickHouse Dev',
        extensionId: 'queryahub.clickhouse-driver',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
    connProdId = await LocalDb.instance.addConnection(
      const ConnectionRow(
        type: 'clickhouse',
        name: 'ClickHouse Prod',
        extensionId: 'queryahub.clickhouse-driver',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    registry.resetForTest();
    sync.resetForTest();
    sync.sync([manifest]);
  });

  tearDown(() {
    sync.resetForTest();
    registry.resetForTest();
  });

  testWidgets(
      'ambiguous target shows a picker with the live connections, and proceeds with the chosen one',
      (tester) async {
    sync.targetOverride = (_, {preferredConnectionId}) =>
        const ExtensionCommandTarget.ambiguous();
    sync.liveConnectionIdsOverride = (_) => [connDevId, connProdId];

    List<ConnectionRow>? shownCandidates;
    final toasts = <String>[];
    sync.toastOverride = toasts.add;
    sync.pickerOverride = (manifest, command, candidates, context) async {
      shownCandidates = candidates;
      return connProdId;
    };
    sync.invokeOverride = null;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      registry['ext.clickhouse.optimize_partition']!.execute(context);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(
      shownCandidates?.map((c) => c.id).toSet(),
      {connDevId, connProdId},
    );
    expect(
      shownCandidates?.map((c) => c.name).toSet(),
      {'ClickHouse Dev', 'ClickHouse Prod'},
    );

    // No live PluginRpcBridge actually exists (only the target/candidate
    // lookups were overridden), so proceeding past the picker reaches the
    // "connect a session" toast rather than a real RPC call — this still
    // proves the chosen connection id flowed through instead of the branch
    // bailing out immediately the way the pre-fix "ambiguous" case did.
    expect(toasts, hasLength(1));
    expect(toasts.single, contains('ClickHouse'));
  });

  testWidgets('cancelling the picker does not run the command or toast',
      (tester) async {
    sync.targetOverride = (_, {preferredConnectionId}) =>
        const ExtensionCommandTarget.ambiguous();
    sync.liveConnectionIdsOverride = (_) => [connDevId, connProdId];

    final toasts = <String>[];
    sync.toastOverride = toasts.add;
    sync.pickerOverride = (manifest, command, candidates, context) async =>
        null; // user dismissed
    sync.invokeOverride = null;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      registry['ext.clickhouse.optimize_partition']!.execute(context);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(toasts, isEmpty);
  });
}
