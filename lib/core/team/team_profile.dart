import 'dart:convert';

import 'package:querya_desktop/core/storage/local_db.dart';

/// Thrown when a team profile file cannot be read.
class TeamProfileFormatException implements Exception {
  const TeamProfileFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Shareable, secret-free snapshot of a set of connections
/// (`team-profile.querya`).
///
/// Passwords, SSH secrets and credentials embedded in connection strings are
/// never written: a teammate fills them in after importing.
class TeamProfileCodec {
  TeamProfileCodec._();

  static const format = 'querya-team-profile';
  static const version = 1;

  /// Option and query-parameter names whose value is a secret (#1564). The
  /// match is a substring of the key, case-insensitive: `privateKey`,
  /// `private_key`, `accessKey`, `db_pwd`, `credentials`, `sig` are all caught.
  static final _secretKey = RegExp(
    r'pass(word|phrase)?|pwd|secret|token|api_?key|private_?key|access_?key|'
    r'credential|signature',
    caseSensitive: false,
  );

  /// Serializes [connections] to profile JSON without any secret.
  static String encode(List<ConnectionRow> connections) {
    final doc = {
      'format': format,
      'version': version,
      'connections': [for (final c in connections) _encodeRow(c)],
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  static Map<String, Object?> _encodeRow(ConnectionRow c) {
    final options = _sanitizeOptions(c.driverOptions);
    final url = _stripUrlCredentials(c.connectionString);
    return {
      'type': c.type,
      'name': c.name,
      if (c.host != null) 'host': c.host,
      if (c.port != null) 'port': c.port,
      if (c.username != null && c.username!.isNotEmpty) 'username': c.username,
      if (c.databaseName != null) 'databaseName': c.databaseName,
      if (c.authSource != null) 'authSource': c.authSource,
      if (c.useSSL) 'useSSL': true,
      if (url != null) 'connectionString': url,
      if (c.extensionId != null) 'extensionId': c.extensionId,
      if (options != null) 'driverOptions': options,
    };
  }

  /// Removes user info (`user:password@`) from URL-style connection strings.
  /// Returns null when the value is not a URL or cannot be made safe.
  static String? _stripUrlCredentials(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final query = <String, String>{
      for (final e in uri.queryParameters.entries)
        if (!_secretKey.hasMatch(e.key)) e.key: e.value,
    };
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static String? _sanitizeOptions(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final cleaned = _scrub(jsonDecode(raw));
      if (cleaned is Map && cleaned.isEmpty) return null;
      return jsonEncode(cleaned);
    } catch (_) {
      return null;
    }
  }

  static Object? _scrub(Object? v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (!_secretKey.hasMatch(e.key.toString())) e.key: _scrub(e.value),
      };
    }
    if (v is List) return [for (final x in v) _scrub(x)];
    return v;
  }

  /// Parses profile JSON into connection rows (no ids, no secrets).
  static List<ConnectionRow> decode(String source, {DateTime? now}) =>
      read(source, now: now).rows;

  /// Like [decode], and says how many entries were left out because they were
  /// not objects, had no type or name, or had a field of the wrong type (a
  /// hand-edited or newer file), so the import can report it.
  static ({List<ConnectionRow> rows, int skipped}) read(
    String source, {
    DateTime? now,
  }) {
    final Object? doc;
    try {
      doc = jsonDecode(source);
    } on FormatException {
      throw const TeamProfileFormatException('Not a valid team profile file.');
    }
    if (doc is! Map || doc['format'] != format) {
      throw const TeamProfileFormatException('Not a Querya team profile.');
    }
    final v = doc['version'];
    if (v is! int || v > version) {
      throw TeamProfileFormatException(
          'Unsupported team profile version: $v.');
    }
    final list = doc['connections'];
    if (list is! List) {
      throw const TeamProfileFormatException('Profile has no connections.');
    }
    final stamp = (now ?? DateTime.now()).toIso8601String();
    final rows = <ConnectionRow>[];
    var skipped = 0;
    for (final item in list) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final type = item['type'];
      final name = item['name'];
      if (type is! String || name is! String || name.trim().isEmpty) {
        skipped++;
        continue;
      }
      // A field that is present with the wrong type makes the whole entry
      // unreadable: dropping just that field would import a connection that
      // points somewhere else.
      var unreadable = false;
      T? field<T>(String key) {
        final v = item[key];
        if (v == null) return null;
        if (v is T) return v;
        unreadable = true;
        return null;
      }

      final host = field<String>('host');
      final port = field<int>('port');
      final username = field<String>('username');
      final databaseName = field<String>('databaseName');
      final authSource = field<String>('authSource');
      final extensionId = field<String>('extensionId');
      final url = field<String>('connectionString');
      final options = field<String>('driverOptions');
      if (unreadable) {
        skipped++;
        continue;
      }
      rows.add(ConnectionRow(
        type: type,
        name: name,
        host: host,
        port: port,
        username: username,
        databaseName: databaseName,
        authSource: authSource,
        useSSL: item['useSSL'] == true,
        // Re-check on import: a hand-edited file must not smuggle secrets in.
        connectionString: url == null ? null : _stripUrlCredentials(url),
        extensionId: extensionId,
        driverOptions: options == null ? null : _sanitizeOptions(options),
        createdAt: stamp,
      ));
    }
    return (rows: rows, skipped: skipped);
  }

  /// Imports [rows] into [db], skipping ones that already exist
  /// (same type, name, host, port and database). Returns the added count.
  static Future<int> importInto(
    LocalDb db,
    List<ConnectionRow> rows,
  ) async {
    final existing = await db.getConnections();
    String key(ConnectionRow r) =>
        '${r.type}|${r.name}|${r.host}|${r.port}|${r.databaseName}';
    final known = {for (final e in existing) key(e)};
    var added = 0;
    for (final r in rows) {
      if (!known.add(key(r))) continue;
      await db.addConnection(r);
      added++;
    }
    return added;
  }
}
