import 'package:mongo_dart/mongo_dart.dart';

import '../storage/local_db.dart';
import 'mongodb_connection.dart';

/// Service for managing MongoDB connections.
class MongoService {
  MongoService._();
  static final MongoService instance = MongoService._();

  final Map<int, MongoConnection> _connections = {};

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
      final selector = filter ?? <String, dynamic>{};

      final stream = coll.find(selector);
      final results = <Map<String, dynamic>>[];
      int count = 0;
      await for (final doc in stream) {
        if (skip != null && count < skip) {
          count++;
          continue;
        }
        if (limit != null && results.length >= limit) {
          break;
        }
        results.add(doc);
        count++;
      }
      return results;
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

  /// Opens a temporary [Db] for the given [database], runs [action], then closes.
  Future<T> _withDb<T>(
    MongoConnection connection,
    String database,
    Future<T> Function(Db db) action,
  ) async {
    if (!connection.isConnected) {
      throw StateError('Not connected to MongoDB');
    }
    final dbUri = connection.buildUriForDatabase(database);
    final db = await Db.create(dbUri);
    await db.open();
    try {
      return await action(db);
    } finally {
      await db.close();
    }
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

  /// Updates a single document matched by [filter].
  Future<void> updateDocument(
    MongoConnection connection,
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    return _withDb(connection, database, (db) async {
      final coll = db.collection(collection);
      await coll.updateOne(filter, update);
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
      await coll.deleteOne(filter);
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
