import 'package:querya_desktop/core/database/mongodb_uri.dart';
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

  var uri = Uri.tryParse(trimmed);
  var url = trimmed;
  if (uri == null) {
    // A MongoDB host list (`mongodb://h1:27017,h2:27017/db?replicaSet=rs0`)
    // is valid MongoDB but not a URI Dart parses: read the first seed, the
    // row keeps the whole string (#1309).
    final mongo = MongoUri.tryParse(trimmed);
    if (mongo != null) {
      uri = Uri.tryParse(
        mongo.copyWith(hosts: [mongo.hosts.first]).toString(),
      );
    }
  }
  if (uri == null) {
    // A password with `@`, `/`, `#`, `?` or `:` written as is, as cloud
    // consoles show it (#1315): read the user info up to the last `@` and
    // encode it.
    final recovered = _percentEncodeUserInfo(trimmed);
    final u = recovered == null ? null : Uri.tryParse(recovered);
    if (u != null) {
      uri = u;
      url = recovered!;
    }
  }
  if (uri == null || uri.scheme.isEmpty) {
    return (
      row: null,
      error: trimmed.contains('@')
          ? 'Invalid URL/URI format. If the password contains special '
              'characters, percent-encode them (@ is %40, / is %2F, # is '
              '%23, ? is %3F, : is %3A).'
          : 'Invalid URL/URI format.',
    );
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

  final row = _buildConnectionRow(url, uri, scheme, sslResult.useSSL);
  if (row == null) {
    return (row: null, error: 'Failed to parse connection URL.');
  }
  return (row: row, error: null);
}

/// [input] with the user info (`user:password`, up to the last `@`)
/// percent-encoded, or null when there is none. Only used for a string `Uri`
/// rejected, so an `@` in a path or a query cannot be mistaken for one.
String? _percentEncodeUserInfo(String input) {
  final m = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*://)(.*)$', dotAll: true)
      .firstMatch(input);
  if (m == null) return null;
  final rest = m.group(2)!;
  // The last `@`: a `?` or `/` before it belongs to the password.
  final at = rest.lastIndexOf('@');
  if (at <= 0) return null;
  final userInfo = rest.substring(0, at);
  final colon = userInfo.indexOf(':');
  final user = colon < 0 ? userInfo : userInfo.substring(0, colon);
  final encodedUser = _encodeOnce(user);
  final encoded = colon < 0
      ? encodedUser
      : '$encodedUser:${_encodeOnce(userInfo.substring(colon + 1))}';
  return '${m.group(1)}$encoded${rest.substring(at)}';
}

/// [v] percent-encoded, leaving what already is (`%40` stays `%40`).
String _encodeOnce(String v) => Uri.encodeComponent(v)
    .replaceAllMapped(RegExp(r'%25([0-9A-Fa-f]{2})'), (m) => '%${m.group(1)}');

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
          error: 'Unsupported sslmode "$sslMode" for PostgreSQL. '
              'Supported: disable, require, verify-ca, verify-full.',
        );
      }
      useSSL = sslMode != 'disable';
    }
  } else if (type != 'sqlite') {
    final sslQuery =
        uri.queryParameters['sslmode'] ?? uri.queryParameters['ssl'];
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
      // `sqlite:///C:/data/app.db` is the file `C:/data/app.db`: the slash
      // before a drive letter is the URI's, not the path's.
      if (RegExp(r'^/[A-Za-z]:[/\\]').hasMatch(path)) path = path.substring(1);
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

    authSource =
        uri.queryParameters['authSource'] ?? uri.queryParameters['authsource'];

    if (type == 'postgresql' ||
        type == 'mysql' ||
        type == 'mongodb' ||
        type == 'redis') {
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
    return host == ':memory:'
        ? 'SQLite (Memory)'
        : 'SQLite (${host!.split('/').last})';
  }

  var cleanHost = host ?? 'localhost';
  // `PostgreSQL: [::1]:5432`, not `PostgreSQL: ::1:5432`.
  if (cleanHost.contains(':') && !cleanHost.startsWith('[')) {
    cleanHost = '[$cleanHost]';
  }
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
