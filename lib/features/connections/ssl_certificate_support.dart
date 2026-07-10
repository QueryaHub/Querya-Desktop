import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Querya-standard SSL certificate query parameters (aligned with PostgreSQL).
const kSslRootCertParam = 'sslrootcert';
const kSslCertParam = 'sslcert';
const kSslKeyParam = 'sslkey';

/// MongoDB driver-native TLS file parameters.
const kMongoTlsCaFileParam = 'tlsCAFile';
const kMongoTlsCertificateKeyFileParam = 'tlsCertificateKeyFile';

class SslCertificatePaths {
  const SslCertificatePaths({
    this.rootCert,
    this.clientCert,
    this.clientKey,
  });

  final String? rootCert;
  final String? clientCert;
  final String? clientKey;

  bool get hasAny =>
      _nonEmpty(rootCert) || _nonEmpty(clientCert) || _nonEmpty(clientKey);

  static bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;
}

SslCertificatePaths extractSslCertificatePaths(Uri uri) {
  return SslCertificatePaths(
    rootCert: uri.queryParameters[kSslRootCertParam],
    clientCert: uri.queryParameters[kSslCertParam],
    clientKey: uri.queryParameters[kSslKeyParam],
  );
}

SslCertificatePaths extractSslCertificatePathsFromString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const SslCertificatePaths();
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return const SslCertificatePaths();
  return extractSslCertificatePaths(uri);
}

Map<String, String> sslCertificateQueryParams(SslCertificatePaths paths) {
  final params = <String, String>{};
  if (SslCertificatePaths._nonEmpty(paths.rootCert)) {
    params[kSslRootCertParam] = paths.rootCert!.trim();
  }
  if (SslCertificatePaths._nonEmpty(paths.clientCert)) {
    params[kSslCertParam] = paths.clientCert!.trim();
  }
  if (SslCertificatePaths._nonEmpty(paths.clientKey)) {
    params[kSslKeyParam] = paths.clientKey!.trim();
  }
  return params;
}

Uri applySslCertificatePaths(Uri uri, SslCertificatePaths paths) {
  final params = Map<String, String>.from(uri.queryParameters);
  for (final key in [kSslRootCertParam, kSslCertParam, kSslKeyParam]) {
    params.remove(key);
  }
  params.addAll(sslCertificateQueryParams(paths));
  return uri.replace(queryParameters: params.isEmpty ? null : params);
}

void setOrRemoveSslParam(
  Map<String, String> params,
  String key,
  String value,
) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    params.remove(key);
  } else {
    params[key] = trimmed;
  }
}

Uri syncSslParamsIntoUri(String uriText, SslCertificatePaths paths) {
  final parsed = Uri.tryParse(uriText.trim());
  if (parsed == null) return Uri();
  return applySslCertificatePaths(parsed, paths);
}

SecurityContext? buildSecurityContext(SslCertificatePaths paths) {
  if (!paths.hasAny) return null;
  final context = SecurityContext();
  if (SslCertificatePaths._nonEmpty(paths.clientCert)) {
    context.useCertificateChain(paths.clientCert!.trim());
  }
  if (SslCertificatePaths._nonEmpty(paths.clientKey)) {
    context.usePrivateKey(paths.clientKey!.trim());
  }
  if (SslCertificatePaths._nonEmpty(paths.rootCert)) {
    context.setTrustedCertificates(paths.rootCert!.trim());
  }
  return context;
}

Future<void> pickSslCertificateFile({
  required void Function(String path) onPicked,
}) async {
  const typeGroup = XTypeGroup(
    label: 'PEM files',
    extensions: ['pem', 'crt', 'key', 'cer'],
  );
  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  if (file == null) return;
  onPicked(file.path);
}

/// Maps Querya [sslrootcert]/[sslcert]/[sslkey] params to mongo_dart URI params.
Uri translateQueryaSslParamsForMongo(Uri uri) {
  final params = Map<String, String>.from(uri.queryParameters);
  final root = params.remove(kSslRootCertParam);
  final cert = params.remove(kSslCertParam);
  final key = params.remove(kSslKeyParam);
  if (root != null && root.isNotEmpty) {
    params[kMongoTlsCaFileParam] = root;
  }
  if (cert != null && cert.isNotEmpty) {
    params[kMongoTlsCertificateKeyFileParam] = cert;
  }
  if (key != null && key.isNotEmpty) {
    params[kSslKeyParam] = key;
  }
  return uri.replace(queryParameters: params.isEmpty ? null : params);
}

/// Resolves a client PEM path for mongo_dart when cert and key are separate files.
Future<String?> resolveMongoTlsCertificateKeyFile({
  required String? clientCert,
  required String? clientKey,
}) async {
  final certPath = clientCert?.trim();
  final keyPath = clientKey?.trim();
  if (certPath == null || certPath.isEmpty) return null;
  if (keyPath == null || keyPath.isEmpty) return certPath;

  final certBytes = await File(certPath).readAsString();
  final keyBytes = await File(keyPath).readAsString();
  final dir = await Directory.systemTemp.createTemp('querya_mongo_tls_');
  final merged = File('${dir.path}/client.pem');
  await merged.writeAsString('$certBytes\n$keyBytes\n');
  return merged.path;
}

String buildRedisConnectionUri({
  required String host,
  required int port,
  String? username,
  String? password,
  bool useSSL = false,
  SslCertificatePaths sslPaths = const SslCertificatePaths(),
}) {
  final userInfoParts = <String>[
    if (username != null && username.isNotEmpty) Uri.encodeComponent(username),
    if (password != null && password.isNotEmpty) Uri.encodeComponent(password),
  ];
  final queryParams = sslCertificateQueryParams(sslPaths);
  return Uri(
    scheme: useSSL ? 'rediss' : 'redis',
    userInfo: userInfoParts.isEmpty ? null : userInfoParts.join(':'),
    host: host,
    port: port,
    queryParameters: queryParams.isEmpty ? null : queryParams,
  ).toString();
}
