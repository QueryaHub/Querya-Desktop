import 'package:querya_desktop/core/storage/local_db.dart';

const _supportedSchemes = {
  'postgresql',
  'postgres',
  'mysql',
  'sqlite',
  'mongodb',
  'mongodb+srv',
  'redis',
  'rediss',
};

const _validPostgresSslModes = {
  'disable',
  'require',
  'verify-ca',
  'verify-full',
};

/// Parses a database connection URL into a [ConnectionRow], or returns an error message.
({ConnectionRow? row, String? error}) parseConnectionUrlInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return (row: null, error: 'URL/URI is required.');
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty) {
    return (row: null, error: 'Invalid URL/URI format.');
  }

  final scheme = uri.scheme.toLowerCase();
  if (!_supportedSchemes.contains(scheme)) {
    return (
      row: null,
      error:
          'Unsupported protocol "$scheme". Supported: postgresql, mysql, sqlite, mongodb, redis.',
    );
  }

  final sslResult = _resolveSslForScheme(scheme, uri);
  if (sslResult.error != null) {
    return (row: null, error: sslResult.error);
  }

  final row = _buildConnectionRow(trimmed, uri, scheme, sslResult.useSSL);
  if (row == null) {
    return (row: null, error: 'Failed to parse connection URL.');
  }
  return (row: row, error: null);
}

({bool? useSSL, String? error}) _resolveSslForScheme(String scheme, Uri uri) {
  final type = _schemeToType(scheme);
  if (type == null) return (useSSL: null, error: null);

  var useSSL = scheme == 'rediss';

  if (type == 'postgresql') {
    final sslMode = uri.queryParameters['sslmode']?.toLowerCase() ??
        uri.queryParameters['ssl']?.toLowerCase();
    if (sslMode != null && sslMode.isNotEmpty) {
      if (!_validPostgresSslModes.contains(sslMode)) {
        return (
          useSSL: null,
          error:
              'Unsupported sslmode "$sslMode" for PostgreSQL. '
              'Supported: disable, require, verify-ca, verify-full.',
        );
      }
      useSSL = sslMode != 'disable';
    }
  } else if (type != 'sqlite') {
    final sslQuery = uri.queryParameters['sslmode'] ??
        uri.queryParameters['ssl'];
    if (sslQuery != null) {
      final lowerSsl = sslQuery.toLowerCase();
      if (lowerSsl == 'true' || lowerSsl == 'require') {
        useSSL = true;
      }
    }
  }

  return (useSSL: useSSL, error: null);
}

String? _schemeToType(String scheme) {
  if (scheme == 'postgresql' || scheme == 'postgres') return 'postgresql';
  if (scheme == 'mysql') return 'mysql';
  if (scheme == 'sqlite') return 'sqlite';
  if (scheme == 'mongodb' || scheme == 'mongodb+srv') return 'mongodb';
  if (scheme == 'redis' || scheme == 'rediss') return 'redis';
  return null;
}

ConnectionRow? _buildConnectionRow(
  String url,
  Uri uri,
  String scheme,
  bool? resolvedUseSSL,
) {
  String type;
  int? defaultPort;

  if (scheme == 'postgresql' || scheme == 'postgres') {
    type = 'postgresql';
    defaultPort = 5432;
  } else if (scheme == 'mysql') {
    type = 'mysql';
    defaultPort = 3306;
  } else if (scheme == 'sqlite') {
    type = 'sqlite';
  } else if (scheme == 'mongodb' || scheme == 'mongodb+srv') {
    type = 'mongodb';
    defaultPort = 27017;
  } else if (scheme == 'redis' || scheme == 'rediss') {
    type = 'redis';
    defaultPort = 6379;
  } else {
    return null;
  }

  String? host;
  int? port;
  String? username;
  String? password;
  String? databaseName;
  String? authSource;
  String? connectionString;
  var useSSL = resolvedUseSSL ?? (scheme == 'rediss');

  if (type == 'sqlite') {
    String path;
    if (url.contains(':memory:')) {
      path = ':memory:';
    } else if (url.startsWith('sqlite:///')) {
      path = uri.path;
    } else if (url.startsWith('sqlite://')) {
      path = url.substring(9);
    } else if (url.startsWith('sqlite:')) {
      path = url.substring(7);
    } else {
      path = uri.path;
    }
    host = path;
  } else {
    host = uri.host.isEmpty ? null : uri.host;
    port = uri.hasPort ? uri.port : null;

    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      if (parts.isNotEmpty) {
        username = Uri.decodeComponent(parts[0]);
      }
      if (parts.length > 1) {
        password = Uri.decodeComponent(parts.sublist(1).join(':'));
      }
    }

    databaseName = uri.pathSegments.firstOrNull;
    if (databaseName != null && databaseName.isEmpty) {
      databaseName = null;
    }

    authSource = uri.queryParameters['authSource'] ??
        uri.queryParameters['authsource'];

    if (type == 'postgresql' || type == 'mysql' || type == 'mongodb') {
      connectionString = url;
    }
  }

  final name = _connectionName(type, host, port, databaseName, defaultPort);

  return ConnectionRow(
    type: type,
    name: name,
    host: host,
    port: port ?? defaultPort,
    username: username,
    password: password,
    databaseName: databaseName,
    authSource: authSource,
    useSSL: useSSL,
    connectionString: connectionString,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

String _connectionName(
  String type,
  String? host,
  int? port,
  String? databaseName,
  int? defaultPort,
) {
  if (type == 'sqlite') {
    return host == ':memory:' ? 'SQLite (Memory)' : 'SQLite (${host!.split('/').last})';
  }

  final cleanHost = host ?? 'localhost';
  final cleanPort = port ?? defaultPort;
  final cleanDb = databaseName ?? '';
  final typeName = switch (type) {
    'postgresql' => 'PostgreSQL',
    'mysql' => 'MySQL',
    'mongodb' => 'MongoDB',
    _ => 'Redis',
  };
  if (cleanDb.isNotEmpty) {
    return '$typeName: $cleanDb';
  }
  if (cleanPort != null) {
    return '$typeName: $cleanHost:$cleanPort';
  }
  return '$typeName: $cleanHost';
}
