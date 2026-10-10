import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/local_db_test_support.dart';

void main() {
  group('ErdSavedLayout', () {
    const layout = ErdSavedLayout(
      positions: {'users': Offset(40.04, 80), 'orders': Offset(300, 120.5)},
      collapsed: {'orders'},
      hidden: {'audit'},
      keysOnly: true,
      scale: 0.75,
      translation: Offset(-20, 10),
    );

    test('round-trips through JSON', () {
      final back = ErdSavedLayout.decode(layout.encode())!;
      expect(back.positions['users'], const Offset(40, 80));
      expect(back.positions['orders'], const Offset(300, 120.5));
      expect(back.collapsed, {'orders'});
      expect(back.hidden, {'audit'});
      expect(back.keysOnly, isTrue);
      expect(back.scale, 0.75);
      expect(back.translation, const Offset(-20, 10));
    });

    test('a broken or foreign payload reads as nothing, unknown keys are ignored',
        () {
      expect(ErdSavedLayout.decode('not json'), isNull);
      expect(ErdSavedLayout.decode('[1,2]'), isNull);
      final partial = ErdSavedLayout.decode(
          '{"positions":{"a":[1,2],"b":"x"},"future":{"colour":1}}')!;
      expect(partial.positions, {'a': const Offset(1, 2)});
      expect(partial.scale, isNull);
    });

    test('keepOnly drops tables that no longer exist', () {
      final kept = layout.keepOnly({'users'});
      expect(kept.positions.keys, ['users']);
      expect(kept.collapsed, isEmpty);
      expect(kept.hidden, isEmpty);
      expect(kept.keysOnly, isTrue);
    });
  });

  group('LocalDbErdLayoutStore', () {
    late Directory dir;
    setUpAll(() async => dir = await initTestLocalDb('erd_layouts_'));
    tearDownAll(() => disposeTestLocalDb(dir));

    test('writes, reads, replaces, and goes with its connection', () async {
      final id = await LocalDb.instance.addConnection(ConnectionRow(
        type: 'sqlite',
        name: 'erd',
        host: '/tmp/erd.db',
        createdAt: DateTime.utc(2026).toIso8601String(),
      ));
      const store = LocalDbErdLayoutStore();
      final key = ErdLayoutKey(connectionId: id, scope: 'main');
      final other = ErdLayoutKey(connectionId: id, scope: 'archive');

      expect(await store.read(key), isNull);
      await store.write(
          key, const ErdSavedLayout(positions: {'t': Offset(1, 2)}));
      await store.write(
          key, const ErdSavedLayout(positions: {'t': Offset(3, 4)}));
      await store.write(other, const ErdSavedLayout(keysOnly: true));

      expect((await store.read(key))!.positions['t'], const Offset(3, 4));
      expect((await store.read(other))!.keysOnly, isTrue);

      await LocalDb.instance.removeConnection(id);
      expect(await store.read(key), isNull);
      expect(await store.read(other), isNull);
    });
  });
}
