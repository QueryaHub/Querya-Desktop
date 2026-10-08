import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/mcp/mcp_client_config.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/local_db_test_support.dart';

void main() {
  group('McpClientConfig', () {
    test('Claude Desktop, Cursor and generic use mcpServers', () {
      for (final kind in [
        McpClientKind.claudeDesktop,
        McpClientKind.cursor,
        McpClientKind.generic,
      ]) {
        final json = jsonDecode(McpClientConfig.snippet(kind, '/x/querya-mcp'));
        expect(json, {
          'mcpServers': {
            'querya': {'command': '/x/querya-mcp'},
          },
        });
      }
    });

    test('VS Code uses servers with a stdio type', () {
      final json =
          jsonDecode(McpClientConfig.snippet(McpClientKind.vsCode, r'C:\q.exe'));
      expect(json, {
        'servers': {
          'querya': {'type': 'stdio', 'command': r'C:\q.exe'},
        },
      });
    });

    test('the bundled shim is found next to the app binary', () async {
      final dir = await Directory.systemTemp.createTemp('querya_shim_');
      addTearDown(() => dir.delete(recursive: true));
      final app = File('${dir.path}/querya_desktop')..createSync();
      expect(McpClientConfig.bundledShimPath(appExecutable: app.path), isNull);
      File('${dir.path}/${McpClientConfig.executableName}').createSync();
      expect(McpClientConfig.bundledShimPath(appExecutable: app.path),
          endsWith(McpClientConfig.executableName));
    });
  });

  group('mcp_activity', () {
    late Directory dir;
    setUpAll(() async => dir = await initTestLocalDb('querya_mcp_activity_'));
    tearDownAll(() => disposeTestLocalDb(dir));
    setUp(() => LocalDb.instance.clearMcpActivity());

    McpActivityEntry entry(int i, {String? error}) => McpActivityEntry(
          recordedAt: DateTime.utc(2026, 10, 8, 10, 0, i).toIso8601String(),
          client: 'c',
          tool: 'run_query',
          connectionId: 1,
          connectionName: 'Shop',
          sqlText: 'SELECT $i',
          rowCount: i,
          durationMs: i * 10,
          error: error,
        );

    test('records newest first and round-trips every field', () async {
      await LocalDb.instance.recordMcpActivity(entry(1));
      await LocalDb.instance.recordMcpActivity(entry(2, error: 'boom'));

      final list = await LocalDb.instance.listMcpActivity();
      expect(list.map((e) => e.sqlText), ['SELECT 2', 'SELECT 1']);
      final e = list.first;
      expect(e.id, isNotNull);
      expect(e.client, 'c');
      expect(e.connectionId, 1);
      expect(e.connectionName, 'Shop');
      expect(e.rowCount, 2);
      expect(e.durationMs, 20);
      expect(e.error, 'boom');
    });

    test('keeps only the newest kMcpActivityCap rows', () async {
      for (var i = 0; i < kMcpActivityCap + 5; i++) {
        await LocalDb.instance.recordMcpActivity(entry(i % 60));
      }
      final list = await LocalDb.instance.listMcpActivity(limit: 1000);
      expect(list, hasLength(kMcpActivityCap));
    });

    test('clear empties the log', () async {
      await LocalDb.instance.recordMcpActivity(entry(1));
      await LocalDb.instance.clearMcpActivity();
      expect(await LocalDb.instance.listMcpActivity(), isEmpty);
    });
  });
}
