import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/app/app_lifecycle_cleanup.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/mcp/mcp_server_controller.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/main_screen/main_screen.dart';

import '../../support/querya_theme_test_shell.dart';
import '../helpers/e2e_app_harness.dart';

/// #1053: closing the window stops the MCP server and closes pooled database
/// sessions; settings written in one run are there in the next.
void main() {
  final app = E2eAppHarness(prefix: 'querya_e2e_lifecycle_');
  setUpAll(app.setUpAll);
  tearDownAll(app.tearDownAll);

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(queryaThemeTestShell(
      child: const AppLifecycleCleanup(
        child: material.SizedBox(width: 1400, height: 900, child: MainScreen()),
      ),
    ));
    await E2eAppHarness.settle(tester);
  }

  testWidgets('closing the app stops MCP and closes pooled sessions',
      (tester) async {
    final path = '${app.dataDir.path}/lifecycle.db';
    File(path).createSync();
    final row = ConnectionRow(
      id: 501,
      type: 'sqlite',
      name: 'Lifecycle',
      host: path,
      createdAt: DateTime.utc(2026).toIso8601String(),
    );
    final lease =
        (await tester.runAsync(() => SqliteService.instance.acquire(row)))!;
    expect(lease.connection.isConnected, isTrue);

    final mcp = McpServerController.instance;
    await tester.runAsync(mcp.start);
    expect(mcp.status.value.running, isTrue);
    expect(mcp.endpointFile.existsSync(), isTrue);

    await pumpApp(tester);

    // Close the window: the cleanup runs as the app goes away.
    await tester.pumpWidget(const material.SizedBox.shrink());
    for (var i = 0;
        i < 80 && (mcp.status.value.running || lease.connection.isConnected);
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(mcp.status.value.running, isFalse);
    expect(mcp.endpointFile.existsSync(), isFalse,
        reason: 'no client may find a dead endpoint');
    expect(lease.connection.isConnected, isFalse);
    lease.release();
    await app.close(tester);
  });

  testWidgets('a setting written in one run is read in the next',
      (tester) async {
    await pumpApp(tester);
    await tester
        .runAsync(() => AppSettings.instance.setExportCurrentTheme(true));
    await tester.pumpWidget(const material.SizedBox.shrink());
    await tester.pump();

    await pumpApp(tester);
    final value = await tester
        .runAsync(() => AppSettings.instance.getExportCurrentTheme());
    expect(value, isTrue);
    await tester
        .runAsync(() => AppSettings.instance.setExportCurrentTheme(false));
    await app.close(tester);
  });
}
