import 'package:flutter/foundation.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// MongoDB connection configuration and state.
class MongoConnection {
  MongoConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 27017,
    this.username,
    String? password,
    this.database,
    this.authSource,
    this.useSSL = false,
    this.replicaSet,
    String? connectionString,
  })  : _password = password,
        _connectionString = connectionString;

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  String? _password;
  final String? database;
  final String? authSource;
  final bool useSSL;
  final String? replicaSet;
  String? _connectionString;

  /// Handshake URI for this live session (includes auth). Not persisted; not
  /// exposed via [password] / [connectionString] after [scrubCredentials].
  String? _sessionUri;

  final Map<String, Db> _openedDbs = {};
  final Map<String, Future<Db>> _openingDbs = {};

  String? get password => _password;
  String? get connectionString => _connectionString;

  Db? _db;
  bool _isConnected = false;

  /// Effective database name from [database] configuration or connection URI path.
  String? get effectiveDatabase {
    if (database != null && database!.trim().isNotEmpty) {
      return database!.trim();
    }
    final rawUri = _sessionUri ?? _connectionString;
    if (rawUri != null && rawUri.isNotEmpty) {
      try {
        final parsed = Uri.parse(rawUri);
        final path = parsed.path.replaceFirst('/', '').trim();
        if (path.isNotEmpty) {
          return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Scrubs sensitive in-memory credentials once the network handshake completes.
  ///
  /// Getters [password] and [connectionString] become null. The live session
  /// still authenticates via [_sessionUri] (in-memory only, never written back).
  void scrubCredentials() {
    _sessionUri ??= buildConnectionUri();
    _password = null;
    _connectionString = null;
  }

  /// Builds MongoDB connection URI from configuration.
  String buildConnectionUri({String? pass, String? connStr}) {
    final effectiveConnStr = connStr ?? _connectionString;
    if (effectiveConnStr != null && effectiveConnStr.isNotEmpty) {
      return effectiveConnStr;
    }
    if (pass == null &&
        _sessionUri != null &&
        _sessionUri!.isNotEmpty &&
        (_password == null || _password!.isEmpty)) {
      return _sessionUri!;
    }

    final buffer = StringBuffer('mongodb://');

    // Add authentication if provided
    final effectivePass = pass ?? _password;
    if (username != null && username!.isNotEmpty) {
      buffer.write(Uri.encodeComponent(username!));
      if (effectivePass != null && effectivePass.isNotEmpty) {
        buffer.write(':${Uri.encodeComponent(effectivePass)}');
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
  String buildUriForDatabase(String databaseName, {String? pass, String? connStr}) {
    final baseUri = buildConnectionUri(pass: pass, connStr: connStr);
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

    var effectivePassword = _password;
    var effectiveConnectionString = _connectionString;

    if ((effectivePassword == null || effectivePassword.isEmpty) &&
        (effectiveConnectionString == null || effectiveConnectionString.isEmpty) &&
        id > 0) {
      try {
        final secrets = await ConnectionSecretsStore.readForConnection(id);
        effectivePassword = secrets.password;
        effectiveConnectionString = secrets.connectionString;
      } catch (_) {}
    }

    try {
      final uri = await _effectiveMongoUri(
        pass: effectivePassword,
        connStr: effectiveConnectionString,
      );
      _db = await Db.create(uri);
      await _db!.open();
      _sessionUri = uri;
      _isConnected = true;
      final defaultName = _databaseNameFromUri(uri);
      if (defaultName != null && defaultName.isNotEmpty) {
        _openedDbs[defaultName] = _db!;
      }
      scrubCredentials();
    } catch (e) {
      _isConnected = false;
      _db = null;
      rethrow;
    }
  }

  Future<String> _effectiveMongoUri({String? pass, String? connStr}) async {
    final base = buildConnectionUri(pass: pass, connStr: connStr);
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
    _sessionUri = null;
    _openingDbs.clear();
    final toClose = <Db>{
      ..._openedDbs.values,
      if (_db != null) _db!,
    };
    _openedDbs.clear();
    _db = null;
    for (final db in toClose) {
      try {
        await db.close();
      } catch (e) {
        debugPrint('MongoConnection.disconnect: $e');
      }
    }
  }

  /// Opens (or reuses) a [Db] for [databaseName] on this live session.
  ///
  /// Auth comes from [_sessionUri], not from the scrubbed [password] getter.
  Future<Db> openDatabase(String databaseName) async {
    if (!isConnected) {
      throw StateError('Not connected to MongoDB');
    }
    final existing = _openedDbs[databaseName];
    if (existing != null && existing.isConnected) {
      return existing;
    }
    if (existing != null) {
      _openedDbs.remove(databaseName);
      try {
        await existing.close();
      } catch (_) {}
    }
    return _openingDbs.putIfAbsent(databaseName, () async {
      try {
        final dbUri = buildUriForDatabase(databaseName);
        final db = await Db.create(dbUri);
        try {
          await db.open();
        } catch (_) {
          try {
            await db.close();
          } catch (_) {}
          rethrow;
        }
        _openedDbs[databaseName] = db;
        return db;
      } finally {
        _openingDbs.remove(databaseName);
      }
    });
  }

  static String? _databaseNameFromUri(String uri) {
    final path = Uri.tryParse(uri)?.path.replaceFirst(RegExp(r'^/'), '') ?? '';
    if (path.isEmpty) return null;
    return path.split('/').first;
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
      final adminDb = await openDatabase('admin');
      final result = await adminDb.runCommand({'listDatabases': 1});
      final databases = result['databases'] as List?;
      if (databases == null) return [];

      return databases
          .map((db) => (db as Map)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      final fallback = effectiveDatabase;
      if (fallback != null &&
          fallback.isNotEmpty &&
          fallback.toLowerCase() != 'admin') {
        return [fallback];
      }
      rethrow;
    }
  }

  /// Gets list of collections in a database.
  Future<List<String>> listCollections(String databaseName) async {
    if (!isConnected || _db == null) {
      throw StateError('Not connected to MongoDB');
    }

    try {
      final db = await openDatabase(databaseName);
      final collections = await db.getCollectionNames();
      return collections.whereType<String>().toList();
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
      final db = await openDatabase(databaseName);
      await db.drop();
      _openedDbs.remove(databaseName);
      try {
        await db.close();
      } catch (_) {}
      if (identical(_db, db)) {
        _db = null;
        for (final other in _openedDbs.values) {
          if (other.isConnected) {
            _db = other;
            break;
          }
        }
        _isConnected = _db != null;
      }
    } catch (e) {
      rethrow;
    }
  }
}
