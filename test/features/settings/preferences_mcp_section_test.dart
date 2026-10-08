import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_server_controller.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_mcp_section.dart';

import '../../support/querya_theme_test_shell.dart';

class _Controller extends McpServerController {
  _Controller() : super(endpointFile: File('/nonexistent/mcp.json'), version: 't');

  var enabled = false;
  final enabledCalls = <bool>[];
  var regenerated = 0;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool v) async {
    enabledCalls.add(v);
    enabled = v;
    status.value = v
        ? const McpServerStatus(running: true, port: 40123, clients: 2)
        : McpServerStatus.stopped;
  }

  @override
  Future<void> regenerateToken() async => regenerated++;
}

class _Access implements McpAccessSettings {
  _Access(this.ids);
  final Set<int> ids;
  final changes = <(int, bool)>[];

  @override
  Future<bool> canRead(ConnectionRow row) async => ids.contains(row.id);
  @override
  Future<Set<int>> readableIds() async => {...ids};
  @override
  Future<void> setReadable(int id, bool readable) async {
    changes.add((id, readable));
    readable ? ids.add(id) : ids.remove(id);
  }
}

ConnectionRow _row(int id, String type, String name, {bool prod = false}) {
  final r = ConnectionRow(
    id: id,
    type: type,
    name: name,
    host: 'h',
    createdAt: DateTime.utc(2026).toIso8601String(),
  );
  return prod ? r.withEnvironment(ConnectionEnvironment.production) : r;
}

void main() {
  late _Controller controller;
  late _Access access;
  late List<McpActivityEntry> activity;
  late List<String> clipboard;

  setUp(() {
    controller = _Controller();
    access = _Access({1});
    activity = [];
    clipboard = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.setSurfaceSize(const material.Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(queryaThemeTestShell(
      child: material.SingleChildScrollView(
        child: PreferencesMcpSection(
          controller: controller,
          access: access,
          shimPath: '/opt/querya-desktop/querya-mcp',
          loadConnections: () async => [
            _row(1, 'postgresql', 'Orders DB', prod: true),
            _row(2, 'sqlite', 'Local file'),
            _row(3, 'mongodb', 'Mongo'), // not SQL: hidden
          ],
          loadActivity: () async => activity,
          clearActivity: () async => activity = [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists SQL connections with their shared state', (tester) async {
    await pump(tester);

    expect(find.text('Orders DB'), findsOneWidget);
    expect(find.text('Local file'), findsOneWidget);
    expect(find.text('Mongo'), findsNothing);
    expect(find.text('PROD'), findsOneWidget);

    material.Switch sw(int id) => tester.widget<material.Switch>(find.descendant(
        of: find.byKey(material.ValueKey('mcp_share_$id')),
        matching: find.byType(material.Switch)));
    expect(sw(1).value, isTrue);
    expect(sw(2).value, isFalse);

    await tester.tap(find.byKey(const material.ValueKey('mcp_share_2')));
    await tester.pump();
    expect(access.changes, [(2, true)]);
    expect(sw(2).value, isTrue);
  });

  testWidgets('enabling the server shows its status', (tester) async {
    await pump(tester);
    expect(find.text('Stopped. AI clients cannot connect.'), findsOneWidget);

    await tester.tap(find.byKey(const material.ValueKey('mcp_enabled')));
    await tester.pump();
    await tester.pump();

    expect(controller.enabledCalls, [true]);
    expect(find.text('Running on 127.0.0.1:40123 · 2 clients connected'),
        findsOneWidget);

    await tester.tap(find.byKey(const material.ValueKey('mcp_regenerate')));
    await tester.pump();
    expect(controller.regenerated, 1);
  });

  testWidgets('copy buttons put a config with the shim path on the clipboard',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const material.ValueKey('mcp_copy_claudeDesktop')));
    await tester.pump();
    await tester.tap(find.byKey(const material.ValueKey('mcp_copy_vsCode')));
    await tester.pump();

    expect(clipboard, hasLength(2));
    expect(clipboard.first, contains('"mcpServers"'));
    expect(clipboard.first, contains('/opt/querya-desktop/querya-mcp'));
    expect(clipboard.last, contains('"servers"'));
    expect(clipboard.last, contains('"type": "stdio"'));
    for (final c in clipboard) {
      expect(c, isNot(contains('token')));
    }
    await tester.pump(const Duration(seconds: 6)); // let toasts expire
  });

  testWidgets('recent calls show results and errors, Clear empties the log',
      (tester) async {
    activity = [
      const McpActivityEntry(
        recordedAt: '2026-10-08T10:00:00Z',
        client: 'claude-desktop',
        tool: 'run_query',
        connectionName: 'Orders DB',
        sqlText: 'SELECT count(*) FROM orders',
        rowCount: 1,
        durationMs: 12,
      ),
      const McpActivityEntry(
        recordedAt: '2026-10-08T10:00:05Z',
        client: 'claude-desktop',
        tool: 'run_query',
        sqlText: 'DELETE FROM orders',
        durationMs: 1,
        error: 'Data-modifying statements are not allowed over MCP.',
      ),
    ];
    await pump(tester);

    expect(find.text('SELECT count(*) FROM orders'), findsOneWidget);
    expect(find.text('1 row(s) · 12 ms'), findsOneWidget);
    expect(find.text('Data-modifying statements are not allowed over MCP.'),
        findsOneWidget);

    await tester.tap(find.byKey(const material.ValueKey('mcp_clear_log')));
    await tester.pump();
    await tester.pump();
    expect(find.text('No calls yet'), findsOneWidget);
  });

  testWidgets('without SQL connections an empty state is shown',
      (tester) async {
    await tester.pumpWidget(queryaThemeTestShell(
      child: material.SingleChildScrollView(
        child: PreferencesMcpSection(
          controller: controller,
          access: access,
          shimPath: null,
          loadConnections: () async => [],
          loadActivity: () async => [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('No SQL connections'), findsOneWidget);
  });
}
