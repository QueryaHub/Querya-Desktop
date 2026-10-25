import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

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

  static bool _nonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;
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
  if (uri != null) return extractSslCertificatePaths(uri);
  // Not a URI Dart accepts (a MongoDB host list, `h1:27017,h2:27017`): the
  // certificate paths are still in its query.
  final q = raw.indexOf('?');
  if (q < 0) return const SslCertificatePaths();
  var query = raw.substring(q + 1);
  final hash = query.indexOf('#');
  if (hash >= 0) query = query.substring(0, hash);
  try {
    final params = Uri.splitQueryString(query);
    return SslCertificatePaths(
      rootCert: params[kSslRootCertParam],
      clientCert: params[kSslCertParam],
      clientKey: params[kSslKeyParam],
    );
  } catch (e) {
    logIgnored('ssl_certificate_support.paths', e);
    return const SslCertificatePaths();
  }
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
  final context = SecurityContext(withTrustedRoots: true);
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

/// Prefix used for temporary MongoDB TLS certificate files.
const kMongoTlsTempPrefix = 'querya_mongo_tls_';

/// Resolves a client PEM path for mongo_dart when cert and key are separate files.
///
/// Sets restrictive file permissions (0600 file / 0700 dir on POSIX) to protect
/// the plaintext private key from unauthorized local access.
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
  // The pid in the name lets another instance's start-up cleanup see that this
  // directory is in use.
  final dir = await Directory.systemTemp
      .createTemp('$kMongoTlsTempPrefix${pid}_');
  final merged = File('${dir.path}/client.pem');
  try {
    if (!Platform.isWindows) {
      await _chmod('700', dir.path, 'TLS temp directory');
      // Empty and 0600 before the key goes in, so it is never readable with
      // the default mode.
      await merged.create();
      await _chmod('600', merged.path, 'TLS client key file');
    }
    await merged.writeAsString('$certBytes\n$keyBytes\n', flush: true);
  } catch (_) {
    await cleanupMongoTlsTempFile(merged.path);
    rethrow;
  }
  return merged.path;
}

/// `Process.run` does not throw on a non-zero exit, so check it: a key file
/// that stayed at the default mode must not be handed out silently.
Future<void> _chmod(String mode, String path, String what) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not restrict permissions of the $what: ${result.stderr}'.trim(),
      path,
    );
  }
}

/// Reliably deletes a temporary MongoDB TLS certificate file and its parent temp directory.
Future<void> cleanupMongoTlsTempFile(String? filePath) async {
  if (filePath == null || filePath.trim().isEmpty) return;
  try {
    final file = File(filePath);
    final parent = file.parent;
    final parentName =
        parent.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    // Security check: ONLY delete if it is inside our querya_mongo_tls_ directory.
    if (!parentName.startsWith(kMongoTlsTempPrefix)) {
      return;
    }
    if (await file.exists()) {
      await file.delete();
    }
    if (await parent.exists()) {
      await parent.delete(recursive: true);
    }
  } catch (e) {
    logIgnored('ssl_certificate_support', e);
  }
}

final _tlsTempOwnerPid = RegExp('^$kMongoTlsTempPrefix(\\d+)_');

Future<bool> _isProcessAlive(int owner) async {
  if (owner == pid) return true;
  try {
    if (Platform.isWindows) {
      final result =
          await Process.run('tasklist', ['/FI', 'PID eq $owner', '/NH']);
      return result.exitCode != 0 || '${result.stdout}'.contains('$owner');
    }
    return (await Process.run('kill', ['-0', '$owner'])).exitCode == 0;
  } catch (e) {
    // Cannot tell: leave the directory alone.
    logIgnored('ssl_certificate_support', e);
    return true;
  }
}

/// Cleans up stale temporary MongoDB TLS directories left from previous
/// sessions. A directory named for a process that is still running belongs to
/// another Querya instance and is kept; [isProcessAlive] is for tests.
Future<void> cleanupStaleMongoTlsTempFiles({
  Future<bool> Function(int pid)? isProcessAlive,
}) async {
  final alive = isProcessAlive ?? _isProcessAlive;
  try {
    final tempDir = Directory.systemTemp;
    if (!await tempDir.exists()) return;
    await for (final entity in tempDir.list()) {
      if (entity is Directory) {
        final name =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        if (name.startsWith(kMongoTlsTempPrefix)) {
          final owner = _tlsTempOwnerPid.firstMatch(name)?.group(1);
          if (owner != null && await alive(int.parse(owner))) continue;
          try {
            await entity.delete(recursive: true);
          } catch (e) {
            logIgnored('ssl_certificate_support', e);
          }
        }
      }
    }
  } catch (e) {
    logIgnored('ssl_certificate_support', e);
  }
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
