import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/connections/ssl_certificate_support.dart';

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

  /// Returns a connection URI targeting [databaseName].
  ///
  /// When credentials are present and no explicit `authSource` query parameter
  /// exists, the method automatically adds `authSource=<original_db>` (defaults
  /// to `admin`) so that authentication succeeds on databases other than the
  /// one the user was created in.
  String buildUriForDatabase(String databaseName) {
    final baseUri = buildConnectionUri();
    final uri = Uri.parse(baseUri);

    // Determine the authSource that should be used.
    // 1) Already present in the query → keep it.
    // 2) Not present but credentials exist → use the original path db, or
    //    fall back to "admin" (Mongo's default authSource).
    final existingAuthSource = uri.queryParameters['authSource'];
    final hasCredentials =
        uri.userInfo.isNotEmpty || (username != null && username!.isNotEmpty);

    Map<String, String>? newQueryParams;
    if (existingAuthSource == null && hasCredentials) {
      // Original db from the URI path (strip leading '/')
      final origDb = uri.path.replaceFirst('/', '');
      final source = (origDb.isNotEmpty) ? origDb : 'admin';
      newQueryParams = Map<String, String>.from(uri.queryParameters)
        ..['authSource'] = source;
    }

    final newUri = uri.replace(
      path: '/$databaseName',
      queryParameters: newQueryParams ?? uri.queryParameters,
    );
    return newUri.toString();
  }

  /// Connects to MongoDB server.
  Future<void> connect() async {
    if (_isConnected && _db != null) {
      return;
    }

    try {
      final uri = await _effectiveMongoUri();
      _db = await Db.create(uri);
      await _db!.open();
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _db = null;
      rethrow;
    }
  }

  Future<String> _effectiveMongoUri() async {
    final base = buildConnectionUri();
    final parsed = Uri.parse(base);
    final paths = extractSslCertificatePaths(parsed);
    final params = Map<String, String>.from(parsed.queryParameters);
    params.remove(kSslRootCertParam);
    params.remove(kSslCertParam);
    params.remove(kSslKeyParam);

    if (paths.rootCert != null && paths.rootCert!.trim().isNotEmpty) {
      params[kMongoTlsCaFileParam] = paths.rootCert!.trim();
    }
    final clientPem = await resolveMongoTlsCertificateKeyFile(
      clientCert: paths.clientCert,
      clientKey: paths.clientKey,
    );
    if (clientPem != null) {
      params[kMongoTlsCertificateKeyFileParam] = clientPem;
    }
    if (useSSL || paths.hasAny) {
      params['ssl'] = 'true';
    }

    return parsed
        .replace(queryParameters: params.isEmpty ? null : params)
        .toString();
  }

  /// Disconnects from MongoDB server.
  Future<void> disconnect() async {
    _isConnected = false;
    final db = _db;
    _db = null;
    try {
      await db?.close();
    } catch (_) {
      // Connection may already be closed — ignore.
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
      final adminUri = buildUriForDatabase('admin');
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
      final dbUri = buildUriForDatabase(databaseName);
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

  /// Drops (deletes) a database.
  Future<void> dropDatabase(String databaseName) async {
    if (!isConnected || _db == null) {
      throw StateError('Not connected to MongoDB');
    }

    try {
      final dbUri = buildUriForDatabase(databaseName);
      final db = await Db.create(dbUri);
      await db.open();
      try {
        await db.drop();
      } finally {
        await db.close();
      }
    } catch (e) {
      rethrow;
    }
  }
}
