import 'dart:async';

import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/mcp/mcp_redaction.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Why [McpMongoGuard] refused a filter or sort: a stable rule id
/// for the audit log and the message the model reads.
class McpMongoRefusal {
  const McpMongoRefusal(this.rule, this.message);

  final String rule;
  final String message;
}

/// Decides whether a Mongo query document sent by an MCP client may run.
///
/// The tools only ever issue `find`, `count` and `listCollections`, so writes
/// are impossible by construction. What is left to refuse is server-side
/// JavaScript hidden in a query document (`$where`, `$function`,
/// `$accumulator`), documents nested deep enough to be a denial of service,
/// and values that are not documents.
abstract final class McpMongoGuard {
  static const bannedOperators = {r'$where', r'$function', r'$accumulator'};
  static const maxDepth = 12;
  static const maxKeys = 500;

  static McpMongoRefusal? refusal(Object? doc, {required String what}) {
    if (doc == null) return null;
    if (doc is! Map) {
      return McpMongoRefusal(
          'mongo_not_a_document', '$what must be a JSON object.');
    }
    var keys = 0;
    McpMongoRefusal? walk(Object? node, int depth) {
      if (depth > maxDepth) {
        return McpMongoRefusal('mongo_too_deep',
            '$what is nested more than $maxDepth levels deep.');
      }
      if (node is Map) {
        for (final entry in node.entries) {
          if (++keys > maxKeys) {
            return McpMongoRefusal(
                'mongo_too_large', '$what has more than $maxKeys fields.');
          }
          final key = '${entry.key}';
          if (bannedOperators.contains(key)) {
            return McpMongoRefusal('mongo_js_operator',
                '$key runs JavaScript on the server and is not allowed. '
                    'Use plain comparison operators (\$eq, \$gt, \$in, ...).');
          }
          final inner = walk(entry.value, depth + 1);
          if (inner != null) return inner;
        }
      } else if (node is List) {
        for (final item in node) {
          final inner = walk(item, depth + 1);
          if (inner != null) return inner;
        }
      }
      return null;
    }

    return walk(doc, 0);
  }
}

/// One short-lived, read-only session on a MongoDB connection.
abstract interface class McpMongoSession {
  /// Database the tools read from.
  String get database;

  Future<List<String>> listCollections();

  Future<List<Map<String, dynamic>>> find(
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? sort,
    required int limit,
  });

  Future<int> count(String collection, {Map<String, dynamic>? filter});

  Future<void> close();
}

typedef McpMongoSessionFactory = Future<McpMongoSession> Function(
  ConnectionRow row,
);

/// Production session: its own [MongoConnection], never the one the sidebar and
/// explorer share, closed after the call.
class _LiveMongoSession implements McpMongoSession {
  _LiveMongoSession._(this._connection, this.database);

  final MongoConnection _connection;
  @override
  final String database;

  static Future<McpMongoSession> open(ConnectionRow row) async {
    final connection = MongoConnection.fromConnectionRow(row);
    final database = connection.effectiveDatabase;
    if (database == null || database.isEmpty) {
      throw const McpToolException(
          'This connection has no database set. Set one in Querya first.');
    }
    await connection.connect();
    return _LiveMongoSession._(connection, database);
  }

  MongoService get _service => MongoService.instance;

  @override
  Future<List<String>> listCollections() =>
      _connection.listCollections(database);

  @override
  Future<List<Map<String, dynamic>>> find(
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? sort,
    required int limit,
  }) =>
      _service.find(_connection, database, collection,
          filter: filter, sort: sort, limit: limit);

  @override
  Future<int> count(String collection, {Map<String, dynamic>? filter}) =>
      _service.countDocuments(_connection, database, collection,
          filter: filter);

  @override
  Future<void> close() => _connection.disconnect();
}

/// Read-only MongoDB tools for MCP: collections, documents, counts.
///
/// Same three layers as SQL: the per-connection opt-in, a guard on the query
/// documents, and a session of its own that only reads. A user's saved
/// credentials may allow writes; this service never issues one.
class McpMongoService {
  McpMongoService({
    McpAccessPolicy? access,
    Future<List<ConnectionRow>> Function()? loadConnections,
    McpMongoSessionFactory? openSession,
    this.maxDocuments = 100,
    this.timeout = const Duration(seconds: 15),
    this.maxFieldChars = 4096,
  })  : _access = access ?? McpAccessStore.instance,
        _loadConnections =
            loadConnections ?? (() => LocalDb.instance.getConnections()),
        _openSession = openSession ?? _LiveMongoSession.open;

  final McpAccessPolicy _access;
  final Future<List<ConnectionRow>> Function() _loadConnections;
  final McpMongoSessionFactory _openSession;

  final int maxDocuments;
  final Duration timeout;
  final int maxFieldChars;

  /// Shared MongoDB connections, without credentials.
  Future<List<McpConnectionInfo>> listConnections() async {
    final out = <McpConnectionInfo>[];
    for (final row in await _loadConnections()) {
      if (row.id == null || row.type != 'mongodb') continue;
      if (!await _access.canRead(row)) continue;
      out.add(McpConnectionInfo.fromRow(row));
    }
    return out;
  }

  /// Whether [id] is a MongoDB connection (shared or not); the server uses it
  /// to say which tools fit the connection.
  Future<bool> isMongo(int id) async {
    for (final row in await _loadConnections()) {
      if (row.id == id) return row.type == 'mongodb';
    }
    return false;
  }

  Future<List<String>> listCollections(int connectionId) {
    return _withSession(connectionId, (session) async {
      final names = await session.listCollections();
      return [
        for (final n in names)
          if (!n.startsWith('system.')) n,
      ]..sort();
    });
  }

  Future<McpMongoDocuments> find(
    int connectionId,
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? sort,
    int limit = 20,
  }) async {
    _guard(filter, 'filter');
    _guard(sort, 'sort');
    final n = limit.clamp(1, maxDocuments);
    return _withSession(connectionId, (session) async {
      final name = await _knownCollection(session, collection);
      // One more than asked for says whether the result was cut.
      final docs = await session.find(
        name,
        filter: filter,
        sort: sort,
        limit: n + 1,
      );
      final cut = docs.length > n;
      return McpMongoDocuments(
        collection: name,
        documents: [
          for (final d in (cut ? docs.sublist(0, n) : docs))
            _shorten(d) as Map<String, Object?>,
        ],
        truncated: cut,
      );
    });
  }

  Future<int> count(
    int connectionId,
    String collection, {
    Map<String, dynamic>? filter,
  }) async {
    _guard(filter, 'filter');
    return _withSession(connectionId, (session) async {
      final name = await _knownCollection(session, collection);
      return session.count(name, filter: filter);
    });
  }

  static void _guard(Object? doc, String what) {
    final refusal = McpMongoGuard.refusal(doc, what: what);
    if (refusal != null) {
      throw McpToolException(refusal.message, rule: refusal.rule);
    }
  }

  /// The collection must exist, so model input never names one unchecked.
  Future<String> _knownCollection(McpMongoSession session, String name) async {
    final names = await session.listCollections();
    if (names.contains(name)) return name;
    final lower = name.toLowerCase();
    final loose = names.where((n) => n.toLowerCase() == lower).toList();
    if (loose.length == 1) return loose.single;
    throw const McpToolException('Collection not found. Call '
        'list_collections to see the available collections.');
  }

  /// Values the model reads as JSON: BSON types become strings, long strings
  /// are cut with a marker.
  Object? _shorten(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) '${e.key}': _shorten(e.value)};
    }
    if (value is List) return [for (final v in value) _shorten(v)];
    if (value == null || value is num || value is bool) return value;
    final text = value is DateTime ? value.toUtc().toIso8601String() : '$value';
    if (text.length <= maxFieldChars) return text;
    final cut = text.length - maxFieldChars;
    return '${text.substring(0, maxFieldChars)}… [truncated $cut chars]';
  }

  Future<T> _withSession<T>(
    int connectionId,
    Future<T> Function(McpMongoSession session) body,
  ) async {
    final row = await _readableConnection(connectionId);
    McpMongoSession? session;
    try {
      session = await _openSession(row).timeout(timeout);
      return await body(session).timeout(timeout);
    } on McpToolException catch (e) {
      throw McpToolException(McpRedaction.redact(e.message, row: row),
          rule: e.rule);
    } on TimeoutException {
      throw McpToolException(
          'The query exceeded the ${timeout.inSeconds} s time limit.');
    } catch (e) {
      throw McpToolException(McpRedaction.redact('$e', row: row));
    } finally {
      try {
        await session?.close();
      } catch (_) {}
    }
  }

  Future<ConnectionRow> _readableConnection(int id) async {
    for (final row in await _loadConnections()) {
      if (row.id != id) continue;
      if (row.type != 'mongodb' || !await _access.canRead(row)) break;
      return row;
    }
    // Same message for "missing" and "not shared" so ids cannot be probed.
    throw McpToolException(
        'Connection $id is not available. Call list_connections to see the shared connections.');
  }
}

class McpMongoDocuments {
  const McpMongoDocuments({
    required this.collection,
    required this.documents,
    required this.truncated,
  });

  final String collection;
  final List<Map<String, Object?>> documents;
  final bool truncated;

  Map<String, Object?> toJson() => {
        'collection': collection,
        'count': documents.length,
        'truncated': truncated,
        'documents': documents,
      };
}
