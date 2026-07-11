import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';

ExtensionManifest _manifest({
  ExtensionType type = ExtensionType.databaseDriver,
  SandboxCapabilities? sandbox,
}) {
  return ExtensionManifest(
    id: 'test.ext',
    name: 'Test Extension',
    version: '1.0.0',
    publisher: 'Test',
    type: type,
    engines: const {'querya_desktop': '*'},
    sandbox: sandbox,
  );
}

void main() {
  group('SandboxPolicy', () {
    test('manifest without sandbox block is allowed', () {
      expect(SandboxPolicy.validate(_manifest(sandbox: null)), isEmpty);
      expect(SandboxPolicy.isAllowed(_manifest(sandbox: null)), isTrue);
    });

    test('allows compliant database driver declaration', () {
      final manifest = _manifest(
        sandbox: const SandboxCapabilities(
          engine: SandboxEngine.process,
          network: NetworkPermission(
            mode: NetworkPermissionMode.connectionHostOnly,
            allowSsl: true,
          ),
        ),
      );
      expect(SandboxPolicy.validate(manifest), isEmpty);
    });

    test('rejects process engine for non-driver extensions', () {
      final manifest = _manifest(
        type: ExtensionType.theme,
        sandbox: const SandboxCapabilities(engine: SandboxEngine.process),
      );
      expect(
        SandboxPolicy.validate(manifest),
        contains(contains('only allowed for database drivers')),
      );
    });

    test('rejects network access for non-driver extensions', () {
      final manifest = _manifest(
        type: ExtensionType.theme,
        sandbox: const SandboxCapabilities(
          engine: SandboxEngine.quickjs,
          network: NetworkPermission(
            mode: NetworkPermissionMode.connectionHostOnly,
          ),
        ),
      );
      expect(
        SandboxPolicy.validate(manifest),
        contains(contains('Network access is not allowed')),
      );
    });

    test('rejects quota overruns', () {
      final manifest = _manifest(
        sandbox: const SandboxCapabilities(
          engine: SandboxEngine.process,
          filesystem: FilesystemPermission(scratchMb: 500),
          resources: ResourceLimits(memoryMb: 4096, maxOpenFiles: 1024),
        ),
      );
      final errors = SandboxPolicy.validate(manifest);
      expect(errors, hasLength(3));
      expect(errors, contains(contains('Scratch quota')));
      expect(errors, contains(contains('Memory limit')));
      expect(errors, contains(contains('File descriptor limit')));
    });

    test('rejects non-scratch filesystem access and unknown values', () {
      final manifest = _manifest(
        sandbox: SandboxCapabilities.fromJson(const {
          'engine': 'jvm',
          'permissions': {
            'network': {'mode': 'full_internet'},
            'filesystem': {'access': 'full_disk'},
          },
        }),
      );
      final errors = SandboxPolicy.validate(manifest);
      expect(errors, contains(contains('Unknown sandbox engine')));
      expect(errors, contains(contains('Unknown network permission mode')));
      expect(errors, contains(contains('Filesystem access "full_disk"')));
    });

    test('allows embedded engine with no permissions for themes', () {
      final manifest = _manifest(
        type: ExtensionType.theme,
        sandbox: const SandboxCapabilities(engine: SandboxEngine.wasm),
      );
      expect(SandboxPolicy.validate(manifest), isEmpty);
    });

    test('allows 512 MB memory for heavy OLAP drivers', () {
      final manifest = _manifest(
        sandbox: const SandboxCapabilities(
          engine: SandboxEngine.process,
          resources: ResourceLimits(memoryMb: 512),
        ),
      );
      expect(SandboxPolicy.validate(manifest), isEmpty);
    });
  });
}
