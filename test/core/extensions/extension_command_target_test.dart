import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_command_target.dart';

void main() {
  group('isAllowedExtensionCommandId', () {
    test('accepts ext. prefix only', () {
      expect(isAllowedExtensionCommandId('ext.clickhouse.cluster_status'), isTrue);
      expect(isAllowedExtensionCommandId('querya.sql.execute'), isFalse);
      expect(isAllowedExtensionCommandId('clickhouse.cluster_status'), isFalse);
      expect(isAllowedExtensionCommandId(''), isFalse);
    });
  });

  group('resolveExtensionCommandTarget', () {
    String? idFor(int connectionId) => switch (connectionId) {
          1 || 2 => 'queryahub.clickhouse-driver',
          9 => 'other.driver',
          _ => null,
        };

    test('none when no live session for the package', () {
      final target = resolveExtensionCommandTarget(
        extensionId: 'queryahub.clickhouse-driver',
        liveConnectionIds: const [9],
        extensionIdFor: idFor,
      );
      expect(target.kind, ExtensionCommandTargetKind.none);
    });

    test('single live session is ready even without selection', () {
      final target = resolveExtensionCommandTarget(
        extensionId: 'queryahub.clickhouse-driver',
        liveConnectionIds: const [2, 9],
        extensionIdFor: idFor,
      );
      expect(target.kind, ExtensionCommandTargetKind.ready);
      expect(target.connectionId, 2);
    });

    test('prefers the workspace-selected connection', () {
      final target = resolveExtensionCommandTarget(
        extensionId: 'queryahub.clickhouse-driver',
        liveConnectionIds: const [1, 2],
        extensionIdFor: idFor,
        preferredConnectionId: 2,
      );
      expect(target.connectionId, 2);
    });

    test('ambiguous when several live and selection does not match', () {
      final target = resolveExtensionCommandTarget(
        extensionId: 'queryahub.clickhouse-driver',
        liveConnectionIds: const [1, 2],
        extensionIdFor: idFor,
        preferredConnectionId: 9,
      );
      expect(target.kind, ExtensionCommandTargetKind.ambiguous);
      expect(target.connectionId, isNull);
    });
  });
}
