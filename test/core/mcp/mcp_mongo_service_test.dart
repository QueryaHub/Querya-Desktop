import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_mongo_service.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

const _secret = 'Mongo-S3cret-99';

class _Access implements McpAccessPolicy {
  _Access(this.ids);
  final Set<int> ids;

  @override
  Future<bool> canRead(ConnectionRow row) async => ids.contains(row.id);
}

class _FakeSession implements McpMongoSession {
  _FakeSession({
    this.collections = const ['users', 'orders', 'system.views'],
    this.docs = const [],
    this.failWith,
    this.hang = false,
  });

  final List<String> collections;
  final List<Map<String, dynamic>> docs;
  final Object? failWith;
  final bool hang;

  final calls = <String>[];
  Map<String, dynamic>? lastFilter;
  Map<String, dynamic>? lastSort;
  int? lastLimit;
  var closed = false;

  @override
  String get database => 'shop';

  @override
  Future<List<String>> listCollections() async => collections;

  @override
  Future<List<Map<String, dynamic>>> find(
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? sort,
    required int limit,
  }) async {
    calls.add('find $collection');
    lastFilter = filter;
    lastSort = sort;
    lastLimit = limit;
    if (hang) return Completer<List<Map<String, dynamic>>>().future;
    if (failWith != null) throw failWith!;
    return docs.take(limit).toList();
  }

  @override
  Future<int> count(String collection, {Map<String, dynamic>? filter}) async {
    calls.add('count $collection');
    lastFilter = filter;
    return docs.length;
  }

  @override
  Future<void> close() async => closed = true;
}

ConnectionRow _row(int id, String type) => ConnectionRow(
      id: id,
      type: type,
      name: 'conn $id',
      host: 'mongo.internal',
      port: 27017,
      username: 'admin',
      password: _secret,
      databaseName: 'shop',
      createdAt: DateTime.utc(2026).toIso8601String(),
    );

void main() {
  late _FakeSession session;
  late int opened;

  McpMongoService service({
    Set<int> shared = const {1},
    Duration timeout = const Duration(seconds: 5),
    int maxField = 4096,
  }) =>
      McpMongoService(
        access: _Access(shared),
        loadConnections: () async => [
          _row(1, 'mongodb'),
          _row(2, 'mongodb'),
          _row(3, 'postgresql'),
        ],
        openSession: (row) async {
          opened++;
          return session;
        },
        timeout: timeout,
        maxFieldChars: maxField,
      );

  setUp(() {
    session = _FakeSession(docs: [
      {'_id': 'a1', 'name': 'Ann', 'age': 31},
      {'_id': 'a2', 'name': 'Bob', 'age': 25},
      {'_id': 'a3', 'name': 'Cy', 'age': 40},
    ]);
    opened = 0;
  });

  group('McpMongoGuard', () {
    test('plain filters pass', () {
      expect(
          McpMongoGuard.refusal({
            'age': {r'$gt': 30},
            r'$or': [
              {'name': 'Ann'},
              {'name': 'Bob'},
            ],
          }, what: 'filter'),
          isNull);
      expect(McpMongoGuard.refusal(null, what: 'filter'), isNull);
    });

    test('server-side JavaScript is refused, however deep', () {
      for (final doc in [
        {r'$where': 'sleep(1000)'},
        {
          'a': {
            r'$and': [
              {r'$function': {'body': 'x', 'args': [], 'lang': 'js'}},
            ],
          },
        },
        {
          'x': [
            {r'$accumulator': {}},
          ],
        },
      ]) {
        expect(McpMongoGuard.refusal(doc, what: 'filter')?.rule,
            'mongo_js_operator',
            reason: '$doc');
      }
    });

    test('a document nested too deep or too wide is refused', () {
      Map<String, dynamic> deep = {'v': 1};
      for (var i = 0; i < McpMongoGuard.maxDepth + 2; i++) {
        deep = {'n': deep};
      }
      expect(McpMongoGuard.refusal(deep, what: 'filter')?.rule,
          'mongo_too_deep');

      final wide = {
        for (var i = 0; i <= McpMongoGuard.maxKeys; i++) 'k$i': 1,
      };
      expect(McpMongoGuard.refusal(wide, what: 'filter')?.rule,
          'mongo_too_large');
    });

    test('a value that is not a document is refused', () {
      expect(McpMongoGuard.refusal('abc', what: 'filter')?.rule,
          'mongo_not_a_document');
    });
  });

  group('connections and access', () {
    test('only shared MongoDB connections are listed, without credentials',
        () async {
      final list = await service(shared: {1, 3}).listConnections();
      expect(list.map((c) => c.id), [1]);
      final json = jsonEncode([for (final c in list) c.toJson()]);
      for (final leak in [_secret, 'admin', 'mongo.internal', '27017']) {
        expect(json, isNot(contains(leak)), reason: leak);
      }
      expect(list.first.type, 'mongodb');
    });

    test('an unshared, missing or non-Mongo connection is "not available"',
        () async {
      for (final id in [2, 3, 99]) {
        await expectLater(
          service().listCollections(id),
          throwsA(isA<McpToolException>().having(
              (e) => e.message, 'message', contains('not available'))),
          reason: 'connection $id',
        );
      }
      expect(opened, 0, reason: 'no session is opened for them');
    });
  });

  group('tools', () {
    test('list_collections hides system collections, sorted', () async {
      expect(await service().listCollections(1), ['orders', 'users']);
      expect(session.closed, isTrue);
    });

    test('find returns documents and says when it cut the result', () async {
      final r = await service().find(1, 'users', limit: 2);
      expect(r.documents.map((d) => d['name']), ['Ann', 'Bob']);
      expect(r.truncated, isTrue);
      expect(session.lastLimit, 3, reason: 'one more than asked for');

      final all = await service().find(1, 'users', limit: 10);
      expect(all.documents, hasLength(3));
      expect(all.truncated, isFalse);
    });

    test('the limit is capped', () async {
      await service().find(1, 'users', limit: 100000);
      expect(session.lastLimit, 101);
    });

    test('the collection must exist; case is forgiven', () async {
      final r = await service().find(1, 'USERS');
      expect(r.collection, 'users');

      await expectLater(
        service().find(1, 'users; db.dropDatabase()'),
        throwsA(isA<McpToolException>()),
      );
      expect(session.calls.where((c) => c.contains('drop')), isEmpty);
    });

    test('a refused filter never opens a session', () async {
      await expectLater(
        service().find(1, 'users', filter: {r'$where': 'sleep(5000)'}),
        throwsA(isA<McpToolException>()
            .having((e) => e.rule, 'rule', 'mongo_js_operator')),
      );
      await expectLater(
        service().count(1, 'users', filter: {r'$function': {}}),
        throwsA(isA<McpToolException>()
            .having((e) => e.rule, 'rule', 'mongo_js_operator')),
      );
      expect(opened, 0);
    });

    test('count passes the filter', () async {
      expect(await service().count(1, 'users', filter: {'age': 31}), 3);
      expect(session.lastFilter, {'age': 31});
    });

    test('long values are cut and BSON-like values become strings', () async {
      session = _FakeSession(docs: [
        {
          'bio': 'x' * 50,
          'at': DateTime.utc(2026, 1, 2),
          'tags': ['a', 'b'],
          'n': 7,
        },
      ]);
      final r = await service(maxField: 10).find(1, 'users');
      final d = r.documents.single;
      expect(d['bio'], startsWith('xxxxxxxxxx… [truncated 40 chars]'));
      expect(d['at'], '2026-01-02T00:00:00.000Z');
      expect(d['tags'], ['a', 'b']);
      expect(d['n'], 7);
    });
  });

  group('failures', () {
    test('a driver error is returned without the secret', () async {
      session = _FakeSession(
          failWith: StateError('auth failed for admin:$_secret@mongo.internal'));
      await expectLater(
        service().find(1, 'users'),
        throwsA(isA<McpToolException>()
            .having((e) => e.message, 'message', isNot(contains(_secret)))),
      );
      expect(session.closed, isTrue, reason: 'the session is closed on error');
    });

    test('a hanging query becomes a readable timeout and closes the session',
        () async {
      session = _FakeSession(hang: true);
      await expectLater(
        service(timeout: const Duration(milliseconds: 50)).find(1, 'users'),
        throwsA(isA<McpToolException>()
            .having((e) => e.message, 'message', contains('time limit'))),
      );
      expect(session.closed, isTrue);
    });
  });
}
