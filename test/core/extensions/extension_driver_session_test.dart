import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
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
  });
}
