import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_driver_capabilities.dart';
import 'package:querya_desktop/core/extensions/models/extension_object_metadata.dart';
import 'package:querya_desktop/core/extensions/models/extension_server_stats.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

void main() {
  group('ExtensionDriverSession', () {
    test('disconnect is a no-op when no session exists', () async {
      await ExtensionDriverSession.instance.disconnect(424242);
    });

    test('disconnectAll is safe when empty', () async {
      await ExtensionDriverSession.instance.disconnectAll();
    });

    test('ConnectionRow.isExtensionDriver', () {
      const withExt = ConnectionRow(
        type: 'clickhouse',
        name: 'CH',
        extensionId: 'queryahub.clickhouse-driver',
        createdAt: '2026-01-01T00:00:00Z',
      );
      const builtIn = ConnectionRow(
        type: 'postgresql',
        name: 'PG',
        createdAt: '2026-01-01T00:00:00Z',
      );
      expect(withExt.isExtensionDriver, isTrue);
      expect(builtIn.isExtensionDriver, isFalse);
    });

    test('buildExtensionConnectParams uses https when useSSL is true', () {
      const row = ConnectionRow(
        type: 'clickhouse',
        name: 'CH',
        host: 'db.local',
        port: 8443,
        username: 'default',
        databaseName: 'analytics',
        useSSL: true,
        createdAt: '2026-01-01T00:00:00Z',
      );

      final params = ExtensionDriverSession.buildExtensionConnectParams(
        connectionId: 42,
        row: row,
        safeMode: true,
      );

      expect(params['connectionString'], 'https://db.local:8443/analytics');
      expect(params['user'], 'default');
      expect(params['safeMode'], isTrue);
    });

    test('ExtensionDriverCapabilities.fromRpc correctly parses capabilities', () {
      final caps = ExtensionDriverCapabilities.fromRpc({
        'supportsTransactions': true,
        'supportsCancel': true,
        'supportsDDLInspection': true,
        'supportsPrivileges': false,
        'hasServerStats': true,
        'supportsMutations': true,
        'supportsBatchMutations': true,
      });

      expect(caps.supportsTransactions, isTrue);
      expect(caps.supportsCancel, isTrue);
      expect(caps.supportsDDLInspection, isTrue);
      expect(caps.supportsPrivileges, isFalse);
      expect(caps.hasServerStats, isTrue);
      expect(caps.supportsMutations, isTrue);
      expect(caps.supportsBatchMutations, isTrue);

      final json = caps.toJson();
      expect(json['supportsMutations'], isTrue);
      expect(json['supportsBatchMutations'], isTrue);
    });

    test('ExtensionServerStats.fromRpc normalizes metrics map', () {
      final stats = ExtensionServerStats.fromRpc({
        'serverVersion': 'ClickHouse 24.3.1.1',
        'uptimeSeconds': 3600,
        'activeConnections': '12',
        'activeQueries': 3,
        'memoryUsageBytes': 104857600,
        'databaseSizes': {
          'analytics': 50000000,
          'default': 1024,
        },
        'extraMetrics': {
          'read_rows': 100000,
        },
      });

      expect(stats.serverVersion, 'ClickHouse 24.3.1.1');
      expect(stats.uptimeSeconds, 3600);
      expect(stats.activeConnections, 12);
      expect(stats.activeQueries, 3);
      expect(stats.memoryUsageBytes, 104857600);
      expect(stats.databaseSizes['analytics'], 50000000);
      expect(stats.extraMetrics['read_rows'], 100000);
    });

    test('ExtensionObjectMetadata.fromRpc parses DDL and column list', () {
      final metadata = ExtensionObjectMetadata.fromRpc({
        'nodeId': 'events_table',
        'nodeType': 'table',
        'ddl': 'CREATE TABLE events (id UInt64, event_time DateTime) ENGINE = MergeTree() ORDER BY id;',
        'columns': [
          {
            'name': 'id',
            'dataType': 'UInt64',
            'isNullable': false,
            'comment': 'Primary ID',
          },
          {
            'name': 'event_time',
            'dataType': 'DateTime',
            'isNullable': true,
          },
        ],
        'properties': {
          'engine': 'MergeTree',
        },
      });

      expect(metadata.nodeId, 'events_table');
      expect(metadata.nodeType, 'table');
      expect(metadata.ddl, contains('MergeTree()'));
      expect(metadata.columns.length, 2);
      expect(metadata.columns[0].name, 'id');
      expect(metadata.columns[0].dataType, 'UInt64');
      expect(metadata.columns[0].isNullable, isFalse);
      expect(metadata.columns[0].comment, 'Primary ID');
      expect(metadata.properties['engine'], 'MergeTree');
    });

    test('ResourceLimits parses timeout_seconds correctly', () {
      final limits = ResourceLimits.fromJson({
        'memory_mb': 512,
        'max_open_files': 128,
        'timeout_seconds': 600,
      });

      expect(limits.memoryMb, 512);
      expect(limits.maxOpenFiles, 128);
      expect(limits.timeoutSeconds, 600);
      expect(limits.toJson()['timeout_seconds'], 600);
    });

    test('restart disconnects active session and validates extension driver presence', () async {
      const row = ConnectionRow(
        id: 888,
        type: 'postgresql',
        name: 'PG',
        createdAt: '2026-01-01T00:00:00Z',
      );

      await expectLater(
        ExtensionDriverSession.instance.restart(row),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not backed by an installed extension driver'),
        )),
      );
    });
  });
}
