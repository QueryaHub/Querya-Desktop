import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart';

import '../../support/querya_theme_test_shell.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._root);
  final String _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;
}

ConnectionRow _row(String name) => ConnectionRow(
      type: 'postgresql',
      name: name,
      host: '127.0.0.1',
      port: 5432,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_rows_keep_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await LocalDb.initFfi();
    await LocalDb.instance.close();
    await FoldersStorage.instance.reload();
  });

  tearDownAll(() async {
    await LocalDb.instance.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
      'a connection added above another leaves the other row\'s state alone '
      '(#1821)', (tester) async {
    late int zetaId;
    await tester.runAsync(() async {
      zetaId = await LocalDb.instance.addConnection(_row('Zeta'));
    });

    await tester.binding.setSurfaceSize(const material.Size(400, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: queryaDarkMaterialTheme,
        darkTheme: queryaDarkMaterialTheme,
        themeMode: material.ThemeMode.dark,
        builder: (context, child) => material.Material(child: child),
        home: material.SizedBox.expand(
          child: ConnectionsPanel(
            skipInitialDbLoadForTest: true,
            onPostgresOpenSqlWorkspace: (_, {database, schema, name, kind}) {},
          ),
        ),
      ),
    );
    final panel =
        tester.state<ConnectionsPanelState>(find.byType(ConnectionsPanel));
    Future<void> reload() async {
      await tester.runAsync(() async {
        await panel.reloadConnectionsFromDb();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 16));
    }

    await reload();
    final zeta = find.byKey(material.ValueKey('connection-$zetaId'));
    final before = tester.state(zeta);

    await tester.runAsync(() async {
      await LocalDb.instance.addConnection(_row('Alpha'));
    });
    await reload();

    expect(find.text('Alpha'), findsOneWidget);
    expect(identical(tester.state(zeta), before), isTrue,
        reason: 'the Zeta row was rebuilt as a new element');

    await tester.runAsync(() async {
      for (final c in await LocalDb.instance.getConnections()) {
        await LocalDb.instance.removeConnection(c.id!);
      }
    });
  });
}
