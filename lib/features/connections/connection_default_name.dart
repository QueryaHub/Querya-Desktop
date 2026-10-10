/// The name a connection gets when the user leaves the name field empty.
///
/// With a URI the name comes from the URI's host and port, not from the
/// form's host field (which a URI overrides): `Redis: cache.example.com:6380`.
/// The port is the URI's, else [defaultPort]; a `+srv` URI has none. A URI
/// without a host (a multi-host replica set list, a malformed one) gives
/// `Redis (URI)`. Without a URI the name is [fields]:
/// `Redis localhost:6379`.
String defaultConnectionName({
  required String label,
  required int defaultPort,
  required String uri,
  required String fields,
}) {
  final text = uri.trim();
  if (text.isEmpty) return fields;
  final parsed = Uri.tryParse(text);
  if (parsed == null || parsed.host.isEmpty) return '$label (URI)';
  final srv = parsed.scheme.endsWith('+srv');
  if (srv) return '$label: ${parsed.host}';
  final port = parsed.hasPort ? parsed.port : defaultPort;
  return '$label: ${parsed.host}:$port';
}
