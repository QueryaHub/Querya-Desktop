import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/features/redis/redis_key_tree_engine.dart';

void main() {
  group('RedisKeyTreeEngine', () {
    RedisKeyInfo makeKey(String name, [String type = 'string', int ttl = -1]) {
      return RedisKeyInfo(
        name: RedisBulkValue.utf8(name),
        type: type,
        ttl: ttl,
      );
    }

    test('buildTree returns empty tree for empty keys', () {
      final tree = RedisKeyTreeEngine.buildTree(keys: const [], delimiter: ':');
      expect(tree.isEmpty, isTrue);
      expect(tree.rootFolders, isEmpty);
      expect(tree.rootLeaves, isEmpty);
      expect(tree.totalKeyCount, 0);
    });

    test('buildTree groups keys into nested folders by colon delimiter', () {
      final keys = [
        makeKey('user:100:profile'),
        makeKey('user:100:settings'),
        makeKey('user:200:avatar'),
        makeKey('session:xyz'),
        makeKey('standalone_key'),
      ];

      final tree = RedisKeyTreeEngine.buildTree(keys: keys, delimiter: ':');
      expect(tree.isEmpty, isFalse);
      expect(tree.totalKeyCount, 5);

      // Root folders: 'session', 'user'
      expect(tree.rootFolders.map((f) => f.name), ['session', 'user']);
      expect(tree.rootLeaves.map((l) => l.name), ['standalone_key']);

      // 'session' folder
      final sessionFolder = tree.rootFolders[0];
      expect(sessionFolder.fullPrefix, 'session:');
      expect(sessionFolder.folders, isEmpty);
      expect(sessionFolder.leaves.length, 1);
      expect(sessionFolder.leaves.first.name, 'xyz');
      expect(sessionFolder.totalKeyCount, 1);

      // 'user' folder
      final userFolder = tree.rootFolders[1];
      expect(userFolder.fullPrefix, 'user:');
      expect(userFolder.folders.length, 2);
      expect(userFolder.folders.map((f) => f.name), ['100', '200']);
      expect(userFolder.leaves, isEmpty);
      expect(userFolder.totalKeyCount, 3);

      // 'user:100' subfolder
      final user100 = userFolder.folders[0];
      expect(user100.fullPrefix, 'user:100:');
      expect(user100.leaves.length, 2);
      expect(user100.leaves.map((l) => l.name), ['profile', 'settings']);
      expect(user100.totalKeyCount, 2);
      expect(user100.allKeys.length, 2);

      // 'user:200' subfolder
      final user200 = userFolder.folders[1];
      expect(user200.fullPrefix, 'user:200:');
      expect(user200.leaves.length, 1);
      expect(user200.leaves.first.name, 'avatar');

      // userFolder.allKeys returns all 3 nested keys
      final allUserKeys =
          userFolder.allKeys.map((k) => k.name.label).toList();
      expect(allUserKeys, [
        'user:100:profile',
        'user:100:settings',
        'user:200:avatar',
      ]);
    });

    test('buildTree groups by alternative slash or dot delimiter', () {
      final slashKeys = [
        makeKey('api/v1/users'),
        makeKey('api/v1/posts'),
        makeKey('api/v2/users'),
      ];

      final slashTree =
          RedisKeyTreeEngine.buildTree(keys: slashKeys, delimiter: '/');
      expect(slashTree.rootFolders.length, 1);
      expect(slashTree.rootFolders.first.name, 'api');
      expect(slashTree.rootFolders.first.fullPrefix, 'api/');
      expect(slashTree.totalKeyCount, 3);

      final dotKeys = [
        makeKey('com.querya.desktop'),
        makeKey('com.querya.mobile'),
      ];
      final dotTree =
          RedisKeyTreeEngine.buildTree(keys: dotKeys, delimiter: '.');
      expect(dotTree.rootFolders.first.name, 'com');
      expect(dotTree.rootFolders.first.fullPrefix, 'com.');
      expect(dotTree.totalKeyCount, 2);
    });

    test('empty delimiter keeps all keys as root leaves', () {
      final keys = [
        makeKey('user:100:profile'),
        makeKey('cache/item'),
      ];
      final tree = RedisKeyTreeEngine.buildTree(keys: keys, delimiter: '');
      expect(tree.rootFolders, isEmpty);
      expect(tree.rootLeaves.length, 2);
      expect(tree.rootLeaves.map((l) => l.name), ['cache/item', 'user:100:profile']);
    });

    test('handles trailing delimiter gracefully without crashing', () {
      final keys = [
        makeKey('trailing:'),
      ];
      final tree = RedisKeyTreeEngine.buildTree(keys: keys, delimiter: ':');
      expect(tree.rootFolders.length, 1);
      expect(tree.rootFolders.first.name, 'trailing');
      expect(tree.rootFolders.first.leaves.first.name, '(empty)');
    });

    test('empty segments and uneven nesting keep their folders and prefixes (#1523)',
        () {
      final tree = RedisKeyTreeEngine.buildTree(
        keys: [
          makeKey('user:100:profile'),
          makeKey('user:100:Avatar'),
          makeKey('user::x'),
          makeKey(':root'),
          makeKey('trail:'),
          makeKey('plain'),
        ],
        delimiter: ':',
      );

      expect(tree.rootLeaves.map((l) => l.name), ['plain']);
      // '' sorts before 'trail' and 'user'.
      expect(tree.rootFolders.map((f) => f.name), ['', 'trail', 'user']);
      expect(tree.rootFolders.map((f) => f.fullPrefix), [':', 'trail:', 'user:']);

      final empty = tree.rootFolders[0];
      expect(empty.leaves.map((l) => l.name), ['root']);

      final trail = tree.rootFolders[1];
      expect(trail.leaves.map((l) => l.name), ['(empty)']);

      final user = tree.rootFolders[2];
      expect(user.folders.map((f) => f.name), ['', '100']);
      expect(user.folders.map((f) => f.fullPrefix), ['user::', 'user:100:']);
      expect(user.folders[0].leaves.map((l) => l.name), ['x']);
      expect(
        user.folders[1].leaves.map((l) => l.name),
        ['Avatar', 'profile'],
      );
      expect(tree.totalKeyCount, 6);
    });

    test('a multi-character delimiter cuts at every occurrence (#1523)', () {
      final tree = RedisKeyTreeEngine.buildTree(
        keys: [makeKey('a::b::c'), makeKey('a::d')],
        delimiter: '::',
      );
      expect(tree.rootFolders.map((f) => f.name), ['a']);
      final a = tree.rootFolders.single;
      expect(a.fullPrefix, 'a::');
      expect(a.folders.single.name, 'b');
      expect(a.folders.single.fullPrefix, 'a::b::');
      expect(a.folders.single.leaves.map((l) => l.name), ['c']);
      expect(a.leaves.map((l) => l.name), ['d']);
    });

    test('names are ordered case-insensitively, ties keep their input order (#1551)',
        () {
      final flat = RedisKeyTreeEngine.buildTree(
        keys: [
          makeKey('b'),
          makeKey('B'),
          makeKey('a'),
          makeKey('A'),
          makeKey('c'),
        ],
        delimiter: '',
      );
      expect(flat.rootLeaves.map((l) => l.name), ['a', 'A', 'b', 'B', 'c']);

      final nested = RedisKeyTreeEngine.buildTree(
        keys: [
          makeKey('f:Zeta'),
          makeKey('f:alpha'),
          makeKey('f:Beta'),
          makeKey('F:x'),
          makeKey('e:y'),
        ],
        delimiter: ':',
      );
      // 'e' < 'f' / 'F' (equal lower-case: input order, 'f' came first).
      expect(nested.rootFolders.map((f) => f.name), ['e', 'f', 'F']);
      expect(
        nested.rootFolders[1].leaves.map((l) => l.name),
        ['alpha', 'Beta', 'Zeta'],
      );
    });
  });
}
