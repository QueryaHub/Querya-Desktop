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
    for (final connection in _connections.values) {
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

    // Create a new Db connection to the specified database
    final baseUri = connection.buildConnectionUri();
    final uri = Uri.parse(baseUri);
    final dbUri = uri.replace(path: '/$database').toString();
    final db = await Db.create(dbUri);
    await db.open();
    try {
      final cmd = command.map((k, v) => MapEntry(k, v as Object));
      return await db.runCommand(cmd);
    } finally {
      await db.close();
    }
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

    // Create a new Db connection to the specified database
    final baseUri = connection.buildConnectionUri();
    final uri = Uri.parse(baseUri);
    final dbUri = uri.replace(path: '/$database').toString();
    final db = await Db.create(dbUri);
    await db.open();
    try {
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
    } finally {
      await db.close();
    }
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

    // Create a new Db connection to the specified database
    final baseUri = connection.buildConnectionUri();
    final uri = Uri.parse(baseUri);
    final dbUri = uri.replace(path: '/$database').toString();
    final db = await Db.create(dbUri);
    await db.open();
    try {
      final coll = db.collection(collection);
      final pipe = pipeline.map((stage) => stage.map((k, v) => MapEntry(k, v as Object))).toList();
      final result = await coll.aggregate(pipe);
      // aggregate returns a Map, wrap it in a List
      return [Map<String, dynamic>.from(result)];
    } finally {
      await db.close();
    }
  }
}
