/// A MongoDB connection string, split without `Uri.parse`.
///
/// `mongodb://h1:27017,h2:27017/db?replicaSet=rs0` is valid MongoDB but not a
/// URI Dart accepts: the host list reads as a port (`Uri.tryParse` is null,
/// `Uri.parse` throws), so replica-set strings could not be imported, opened
/// or tunnelled (#1309). The pieces here are kept as written: the user info
/// stays percent-encoded.
class MongoUri {
  const MongoUri._({
    required this.scheme,
    required this.userInfo,
    required this.hosts,
    required this.path,
    required this.params,
  });

  /// `mongodb` or `mongodb+srv`, lower case.
  final String scheme;

  /// `user:password` as written (percent-encoded), or null.
  final String? userInfo;

  /// `host`, `host:port` or `[::1]:port`, in order.
  final List<String> hosts;

  /// `''` or `/database`.
  final String path;

  /// Query parameters, decoded, in order.
  final Map<String, String> params;

  bool get isSrv => scheme == 'mongodb+srv';

  /// The database of the path, if there is one.
  String? get databaseName {
    final name = path.replaceFirst(RegExp(r'^/'), '').split('/').first;
    if (name.isEmpty) return null;
    try {
      return Uri.decodeComponent(name);
    } catch (_) {
      return name;
    }
  }

  /// Null when [raw] is not a `mongodb://` / `mongodb+srv://` string with at
  /// least one host.
  static MongoUri? tryParse(String raw) {
    final m = RegExp(r'^(mongodb(?:\+srv)?)://(.*)$',
            caseSensitive: false, dotAll: true)
        .firstMatch(raw.trim());
    if (m == null) return null;
    var rest = m.group(2)!;
    final hash = rest.indexOf('#');
    if (hash >= 0) rest = rest.substring(0, hash);

    var end = rest.length;
    for (final stop in ['/', '?']) {
      final i = rest.indexOf(stop);
      if (i >= 0 && i < end) end = i;
    }
    var authority = rest.substring(0, end);
    final tail = rest.substring(end);

    String? userInfo;
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      userInfo = authority.substring(0, at);
      authority = authority.substring(at + 1);
    }
    final hosts = [
      for (final h in authority.split(','))
        if (h.trim().isNotEmpty) h.trim(),
    ];
    if (hosts.isEmpty) return null;

    var path = '';
    var query = '';
    final q = tail.indexOf('?');
    if (q >= 0) {
      path = tail.substring(0, q);
      query = tail.substring(q + 1);
    } else {
      path = tail;
    }

    final params = <String, String>{};
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = eq < 0 ? pair : pair.substring(0, eq);
      final value = eq < 0 ? '' : pair.substring(eq + 1);
      params[_decode(key)] = _decode(value);
    }
    return MongoUri._(
      scheme: m.group(1)!.toLowerCase(),
      userInfo: userInfo != null && userInfo.isNotEmpty ? userInfo : null,
      hosts: hosts,
      path: path,
      params: params,
    );
  }

  static String _decode(String v) {
    try {
      return Uri.decodeQueryComponent(v);
    } catch (_) {
      return v;
    }
  }

  /// The first seed: host and port (null when none is written).
  ({String host, int? port}) get firstHost {
    final h = hosts.first;
    if (h.startsWith('[')) {
      final close = h.indexOf(']');
      if (close > 0) {
        final port = h.length > close + 2 && h[close + 1] == ':'
            ? int.tryParse(h.substring(close + 2))
            : null;
        return (host: h.substring(1, close), port: port);
      }
    }
    final colon = h.lastIndexOf(':');
    if (colon > 0 && !h.substring(0, colon).contains(':')) {
      return (host: h.substring(0, colon), port: int.tryParse(h.substring(colon + 1)));
    }
    return (host: h, port: null);
  }

  MongoUri copyWith({
    String? scheme,
    List<String>? hosts,
    String? path,
    Map<String, String>? params,
  }) =>
      MongoUri._(
        scheme: scheme ?? this.scheme,
        userInfo: userInfo,
        hosts: hosts ?? this.hosts,
        path: path ?? this.path,
        params: params ?? this.params,
      );

  /// This string pointing at one local tunnel endpoint instead of its seeds.
  ///
  /// The tunnel reaches one server, so the driver must not go looking for the
  /// replica set's other members: `directConnection=true` unless the string
  /// says otherwise. An SRV string names a DNS record, not a host and port a
  /// tunnel could reach, so it cannot be tunnelled.
  MongoUri forTunnel(String host, int port) {
    if (isSrv) {
      throw UnsupportedError(
        'An SSH tunnel cannot be used with a mongodb+srv:// connection '
        'string: it names a DNS record that resolves to hosts the tunnel '
        'cannot know. Use a mongodb:// string with the server\'s host and '
        'port.',
      );
    }
    final bracket = host.contains(':') && !host.startsWith('[');
    return copyWith(
      hosts: ['${bracket ? '[$host]' : host}:$port'],
      params: {'directConnection': 'true', ...params},
    );
  }

  @override
  String toString() {
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$scheme://${userInfo == null ? '' : '$userInfo@'}'
        '${hosts.join(',')}$path${query.isEmpty ? '' : '?$query'}';
  }
}
