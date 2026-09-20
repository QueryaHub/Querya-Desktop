import 'package:mongo_dart/mongo_dart.dart';

import '../storage/local_db.dart';
import 'mongodb_connection.dart';

/// Throws if a single-document write matched nothing (wrong `_id` type,
/// concurrent delete). Same class of lie as 0-row SQL DML.
///
/// [nModified] is ignored: an identical `$set` still matched the document.
void expectMongoDocumentMatched(int matched, {required String operation}) {
  if (matched >= 1) return;
  throw StateError(
    '$operation failed: matched 0 documents. '
    'The document may have been deleted or the _id type does not match.',
  );
}

void _throwIfMongoWriteFailed(
  WriteResult result, {
  required String operation,
  required int matched,
}) {
  if (result.hasWriteErrors) {
    throw StateError(
      '$operation failed: ${result.writeError?.errmsg ?? 'write error'}',
    );
  }
  expectMongoDocumentMatched(matched, operation: operation);
}

/// Service for managing MongoDB connections.
class MongoService {
  MongoService._();
  static final MongoService instance = MongoService._();

  final Map<int, MongoConnection> _connections = {};

  /// Returns a connected [MongoConnection] for [row], reusing an existing
  /// pooled connection when it is already open for the same connection id.
  ///
  /// Use this from the sidebar and explorer so they share one socket per saved
  /// connection instead of opening parallel clients.
  Future<MongoConnection> ensureConnected(ConnectionRow row) async {
    if (row.type != 'mongodb') {
      throw ArgumentError('Connection type must be mongodb');
    }
    final id = row.id ?? 0;
    final existing = _connections[id];
    if (existing != null && existing.isConnected) {
      return existing;
    }
    final connection = createConnection(row);
    await connection.connect();
    return connection;
  }

  /// Disconnects the pooled connection for [id], if any (e.g. when the user
  /// removes the connection from the browser).
  Future<void> disconnectByConnectionId(int id) async {
    final c = _connections[id];
    if (c != null) {
      await disconnect(c);
    }
  }

  /// Creates (or replaces) a [MongoConnection] for the given [ConnectionRow].
  /// If a connection with the same ID already exists it is disconnected first.
  MongoConnection createConnection(ConnectionRow row) {
    if (row.type != 'mongodb') {
      throw ArgumentError('Connection type must be mongodb');
    }

    final id = row.id ?? 0;

    // Disconnect previous connection for this ID, if any.
    final existing = _connections[id];
    if (existing != null) {
      existing.disconnect(); // fire-and-forget; disconnect is safe
    }

    final connection = MongoConnection(
      id: id,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 27017,
      username: row.username,
      password: row.password,
      database: row.databaseName,
      authSource: row.authSource,
      useSSL: row.useSSL,
      connectionString: row.connectionString,
    );

    _connections[connection.id] = connection;
    return connection;
  }

  /// Gets an active connection by ID.
  MongoConnection? getConnection(int id) {
    return _connections[id];
  }

  /// Connects to MongoDB using the connection configuration.
  Future<void> connect(MongoConnection connection) async {
    await connection.connect();
  }

  /// Disconnects from MongoDB.
  Future<void> disconnect(MongoConnection connection) async {
    await connection.disconnect();
    _connections.remove(connection.id);
  }

  /// Disconnects all connections.
  Future<void> disconnectAll() async {
    for (final connection in _connections.values.toList()) {
      await disconnect(connection);
    }
  }

  /// Executes a MongoDB command.
  Future<Map<String, dynamic>> executeCommand(
    MongoConnection connection,
    String database,
    Map<String, dynamic> command,
  ) async {
    if (!connection.isConnected) {
      throw StateError('Not connected to MongoDB');
    }

    return _withDb(connection, database, (db) async {
      final cmd = command.map((k, v) => MapEntry(k, v as Object));
      return await db.runCommand(cmd);
    });
  }

  /// Executes a find query.
  Future<List<Map<String, dynamic>>> find(
    MongoConnection connection,
    String database,
    String collection, {
    Map<String, dynamic>? filter,
    Map<String, dynamic>? projection,
    Map<String, dynamic>? sort,
    int? limit,
    int? skip,
  }) async {
    if (!connection.isConnected) {
      throw StateError('Not connected to MongoDB');
    }

    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);

      final selector = where;
      if (filter != null && filter.isNotEmpty) {
        selector.raw(filter);
      }
      if (sort != null && sort.isNotEmpty) {
        for (final entry in sort.entries) {
          final isDesc = entry.value == -1 ||
              entry.value == 'desc' ||
              entry.value == 'DESC';
          selector.sortBy(entry.key, descending: isDesc);
        }
      }
      if (skip != null && skip > 0) {
        selector.skip(skip);
      }
      if (limit != null && limit > 0) {
        selector.limit(limit);
      }

      final stream = coll.find(selector);
      return await stream.toList();
    });
  }

  /// Executes an aggregation pipeline.
  Future<List<Map<String, dynamic>>> aggregate(
    MongoConnection connection,
    String database,
    String collection,
    List<Map<String, dynamic>> pipeline,
  ) async {
    if (!connection.isConnected) {
      throw StateError('Not connected to MongoDB');
    }

    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      final pipe = pipeline
          .map((stage) => stage.map((k, v) => MapEntry(k, v as Object)))
          .toList();
      final result = await coll.aggregate(pipe);
      // aggregate returns a Map, wrap it in a List
      return [Map<String, dynamic>.from(result)];
    });
  }

  /// Reuses a pooled [Db] for [database] on the live session (auth via the
  /// in-memory session URI, not the scrubbed password getter).
  Future<T> _withDb<T>(
    MongoConnection connection,
    String database,
    Future<T> Function(Db db) action,
  ) async {
    if (!connection.isConnected) {
      throw StateError('Not connected to MongoDB');
    }
    final db = await connection.openDatabase(database);
    return await action(db);
  }

  /// Returns the document count for a collection (with optional filter).
  Future<int> countDocuments(
    MongoConnection connection,
    String database,
    String collection, {
    Map<String, dynamic>? filter,
  }) async {
    return _withDb(connection, database, (db) async {
      final result = await db.runCommand(<String, Object>{
        'count': collection,
        if (filter != null && filter.isNotEmpty) 'query': filter,
      });
      final n = result['n'];
      if (n is int) return n;
      if (n is num) return n.toInt();
      return int.tryParse(n.toString()) ?? 0;
    });
  }

  /// Returns `collStats` for a collection.
  Future<Map<String, dynamic>> getCollectionStats(
    MongoConnection connection,
    String database,
    String collection,
  ) async {
    return _withDb(connection, database, (db) async {
      return await db.runCommand(<String, Object>{'collStats': collection});
    });
  }

  /// Inserts a single document, returns the inserted document (with _id).
  Future<Map<String, dynamic>> insertDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> document,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      await coll.insertOne(document);
      return document;
    });
  }

  /// Updates a single document matched by [filter] (`$set` / `$unset` / …).
  Future<void> updateDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      final result = await coll.updateOne(filter, update);
      _throwIfMongoWriteFailed(
        result,
        operation: 'updateOne',
        matched: result.nMatched,
      );
    });
  }

  /// Replaces a single document matched by [filter] (full-document Save).
  Future<void> replaceDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> replacement,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      final result = await coll.replaceOne(filter, replacement);
      _throwIfMongoWriteFailed(
        result,
        operation: 'replaceOne',
        matched: result.nMatched,
      );
    });
  }

  /// Deletes a single document matched by [filter].
  Future<void> deleteDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      final result = await coll.deleteOne(filter);
      _throwIfMongoWriteFailed(
        result,
        operation: 'deleteOne',
        matched: result.nRemoved,
      );
    });
  }

  /// Returns index information for a collection.
  Future<List<Map<String, dynamic>>> getIndexes(
    MongoConnection connection,
    String database,
    String collection,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      final indexes = await coll.getIndexes();
      return indexes.cast<Map<String, dynamic>>();
    });
  }

  /// Creates a new collection.
  Future<void> createCollection(
    MongoConnection connection,
    String database,
    String collectionName,
  ) async {
    return _withDb(connection, database, (db) async {
      await db.createCollection(collectionName);
    });
  }

  /// Drops a collection.
  Future<void> dropCollection(
    MongoConnection connection,
    String database,
    String collectionName,
  ) async {
    return _withDb(connection, database, (db) async {
      await db.dropCollection(collectionName);
    });
  }
}
