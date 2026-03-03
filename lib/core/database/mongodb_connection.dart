import 'package:mongo_dart/mongo_dart.dart';

/// MongoDB connection configuration and state.
class MongoConnection {
  MongoConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 27017,
    this.username,
    this.password,
    this.database,
    this.authSource,
    this.useSSL = false,
    this.replicaSet,
    this.connectionString,
  });

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String? database;
  final String? authSource;
  final bool useSSL;
  final String? replicaSet;
  final String? connectionString;

  Db? _db;
  bool _isConnected = false;

  /// Builds MongoDB connection URI from configuration.
  String buildConnectionUri() {
    if (connectionString != null && connectionString!.isNotEmpty) {
      return connectionString!;
    }

    final buffer = StringBuffer('mongodb://');

    // Add authentication if provided
    if (username != null && username!.isNotEmpty) {
      buffer.write(Uri.encodeComponent(username!));
      if (password != null && password!.isNotEmpty) {
        buffer.write(':${Uri.encodeComponent(password!)}');
      }
      buffer.write('@');
    }

    // Add host and port
    buffer.write(host);
    if (port != 27017) {
      buffer.write(':$port');
    }

    // Add database
    if (database != null && database!.isNotEmpty) {
      buffer.write('/$database');
    }

    // Add query parameters
    final params = <String>[];
    if (authSource != null && authSource!.isNotEmpty) {
      params.add('authSource=${Uri.encodeComponent(authSource!)}');
    }
    if (replicaSet != null && replicaSet!.isNotEmpty) {
      params.add('replicaSet=${Uri.encodeComponent(replicaSet!)}');
    }
    if (useSSL) {
      params.add('ssl=true');
    }

    if (params.isNotEmpty) {
      buffer.write('?${params.join('&')}');
    }

    return buffer.toString();
  }

  /// Connects to MongoDB server.
  Future<void> connect() async {
    if (_isConnected && _db != null) {
      return;
    }

    try {
      final uri = buildConnectionUri();
      _db = await Db.create(uri);
      await _db!.open();
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _db = null;
      rethrow;
    }
  }

  /// Disconnects from MongoDB server.
  Future<void> disconnect() async {
    if (_db != null && _isConnected) {
      await _db!.close();
      _db = null;
      _isConnected = false;
    }
  }

  /// Checks if connection is active.
  bool get isConnected => _isConnected && _db != null && _db!.isConnected;

  /// Gets the database instance.
  Db? get db => _db;

  /// Gets list of database names.
  Future<List<String>> listDatabases() async {
    if (!isConnected || _db == null) {
      throw StateError('Not connected to MongoDB');
    }

    try {
      // Switch to admin database to list all databases
      final adminUri = buildConnectionUri().replaceAll(RegExp(r'/[^/?]*(\?|$)'), '/admin\$1');
      final adminDb = await Db.create(adminUri);
      await adminDb.open();
      try {
        final result = await adminDb.runCommand({'listDatabases': 1});
        final databases = result['databases'] as List?;
        if (databases == null) return [];

        return databases
            .map((db) => (db as Map)['name'] as String)
            .where((name) => name.isNotEmpty)
            .toList();
      } finally {
        await adminDb.close();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Gets list of collections in a database.
  Future<List<String>> listCollections(String databaseName) async {
    if (!isConnected || _db == null) {
      throw StateError('Not connected to MongoDB');
    }

    try {
      // Create a new Db connection to the specified database
      final dbUri = buildConnectionUri().replaceAll(RegExp(r'/[^/?]*(\?|$)'), '/$databaseName\$1');
      final db = await Db.create(dbUri);
      await db.open();
      try {
        final collections = await db.getCollectionNames();
        return collections.whereType<String>().toList();
      } finally {
        await db.close();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Tests the connection.
  Future<bool> testConnection() async {
    try {
      await connect();
      if (_db != null) {
        await _db!.runCommand({'ping': 1});
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
