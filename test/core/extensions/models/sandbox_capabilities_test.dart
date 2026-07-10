import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';

void main() {
  group('SandboxCapabilities', () {
    test('parses full sandbox block from Block E spec example', () {
      final capabilities = SandboxCapabilities.fromJson(const {
        'engine': 'process',
        'permissions': {
          'network': {'mode': 'connection_host_only', 'allow_ssl': true},
          'filesystem': {'scratch_mb': 100, 'access': 'scratch_only'},
          'resources': {'memory_mb': 256, 'max_open_files': 64},
        },
      });

      expect(capabilities.engine, SandboxEngine.process);
      expect(capabilities.network.mode, NetworkPermissionMode.connectionHostOnly);
      expect(capabilities.network.allowSsl, isTrue);
      expect(capabilities.filesystem.scratchMb, 100);
      expect(capabilities.filesystem.access, 'scratch_only');
      expect(capabilities.resources.memoryMb, 256);
      expect(capabilities.resources.maxOpenFiles, 64);
    });

    test('applies safe defaults when permissions are omitted', () {
      final capabilities = SandboxCapabilities.fromJson(const {
        'engine': 'wasm',
      });

      expect(capabilities.engine, SandboxEngine.wasm);
      expect(capabilities.engine.isEmbedded, isTrue);
      expect(capabilities.network.mode, NetworkPermissionMode.none);
      expect(capabilities.network.allowSsl, isFalse);
      expect(capabilities.filesystem.scratchMb,
          FilesystemPermission.defaultScratchMb);
      expect(capabilities.resources.memoryMb, ResourceLimits.defaultMemoryMb);
      expect(capabilities.resources.maxOpenFiles,
          ResourceLimits.defaultMaxOpenFiles);
    });

    test('maps unknown engine and network mode to unknown', () {
      final capabilities = SandboxCapabilities.fromJson(const {
        'engine': 'jvm',
        'permissions': {
          'network': {'mode': 'full_internet'},
        },
      });

      expect(capabilities.engine, SandboxEngine.unknown);
      expect(capabilities.network.mode, NetworkPermissionMode.unknown);
    });

    test('toJson round-trips through fromJson', () {
      const original = SandboxCapabilities(
        engine: SandboxEngine.process,
        network: NetworkPermission(
          mode: NetworkPermissionMode.connectionHostOnly,
          allowSsl: true,
        ),
        filesystem: FilesystemPermission(scratchMb: 50),
        resources: ResourceLimits(memoryMb: 512, maxOpenFiles: 32),
      );

      final restored = SandboxCapabilities.fromJson(original.toJson());

      expect(restored.engine, original.engine);
      expect(restored.network.mode, original.network.mode);
      expect(restored.network.allowSsl, original.network.allowSsl);
      expect(restored.filesystem.scratchMb, original.filesystem.scratchMb);
      expect(restored.resources.memoryMb, original.resources.memoryMb);
      expect(restored.resources.maxOpenFiles, original.resources.maxOpenFiles);
    });
  });

  group('ExtensionManifest sandbox integration', () {
    test('fromJson parses sandbox block and toJson serializes it back', () {
      final manifest = ExtensionManifest.fromJson(const {
        'id': 'queryahub.clickhouse-driver',
        'name': 'ClickHouse Driver',
        'version': '1.0.0',
        'publisher': 'QueryaHub',
        'type': 'database_driver',
        'engines': {'querya_desktop': '^0.5.0'},
        'main': 'bin/clickhouse_rpc_server',
        'sandbox': {
          'engine': 'process',
          'permissions': {
            'network': {'mode': 'connection_host_only', 'allow_ssl': true},
            'filesystem': {'scratch_mb': 100, 'access': 'scratch_only'},
            'resources': {'memory_mb': 256, 'max_open_files': 64},
          },
        },
      });

      expect(manifest.type, ExtensionType.databaseDriver);
      expect(manifest.sandbox, isNotNull);
      expect(manifest.sandbox!.engine, SandboxEngine.process);

      final json = manifest.toJson();
      expect(json['sandbox'], isA<Map<String, dynamic>>());
      final restored = ExtensionManifest.fromJson(json);
      expect(restored.sandbox!.network.mode,
          NetworkPermissionMode.connectionHostOnly);
      expect(restored.sandbox!.resources.memoryMb, 256);
    });

    test('manifest without sandbox block keeps sandbox null and omits key', () {
      final manifest = ExtensionManifest.fromJson(const {
        'id': 'community.nord-theme',
        'name': 'Nord Theme',
        'version': '0.8.2',
        'publisher': 'Community',
        'type': 'theme',
        'engines': {'querya_desktop': '*'},
      });

      expect(manifest.sandbox, isNull);
      expect(manifest.toJson().containsKey('sandbox'), isFalse);
    });
  });
}
