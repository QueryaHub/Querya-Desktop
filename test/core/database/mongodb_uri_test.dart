import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_uri.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';

/// #1309: replica-set connection strings.
void main() {
  const replicaSet =
      'mongodb://app:s3cret@db1.example:27017,db2.example:27018/shop'
      '?replicaSet=rs0&authSource=admin';

  group('MongoUri', () {
    test('reads a host list that Uri.parse rejects', () {
      expect(Uri.tryParse(replicaSet), isNull);

      final u = MongoUri.tryParse(replicaSet)!;
      expect(u.scheme, 'mongodb');
      expect(u.userInfo, 'app:s3cret');
      expect(u.hosts, ['db1.example:27017', 'db2.example:27018']);
      expect(u.databaseName, 'shop');
      expect(u.params, {'replicaSet': 'rs0', 'authSource': 'admin'});
      expect(u.firstHost, (host: 'db1.example', port: 27017));
      expect(u.toString(), replicaSet);
    });

    test('a single host, no database, no port, an SRV scheme', () {
      final single = MongoUri.tryParse('mongodb://localhost')!;
      expect(single.hosts, ['localhost']);
      expect(single.databaseName, isNull);
      expect(single.firstHost, (host: 'localhost', port: null));

      final srv = MongoUri.tryParse('MongoDB+SRV://u:p@cluster0.example/app')!;
      expect(srv.isSrv, isTrue);
      expect(srv.scheme, 'mongodb+srv');
      expect(srv.firstHost.host, 'cluster0.example');
    });

    test('a percent-encoded @ in the password stays in the user info', () {
      final u = MongoUri.tryParse('mongodb://u:p%40ss@h1:27017,h2:27017/db')!;
      expect(u.userInfo, 'u:p%40ss');
      expect(u.hosts, ['h1:27017', 'h2:27017']);
    });

    test('an IPv6 seed and things that are not MongoDB', () {
      expect(MongoUri.tryParse('mongodb://[::1]:27018/db')!.firstHost,
          (host: '::1', port: 27018));
      expect(MongoUri.tryParse('postgres://h/db'), isNull);
      expect(MongoUri.tryParse('mongodb://'), isNull);
      expect(MongoUri.tryParse('not a uri'), isNull);
    });

    test('a tunnel is one local endpoint, direct, and not for SRV', () {
      final t = MongoUri.tryParse(replicaSet)!.forTunnel('127.0.0.1', 50111);
      expect(t.hosts, ['127.0.0.1:50111']);
      expect(t.params['directConnection'], 'true');
      expect(t.params['replicaSet'], 'rs0');
      expect(t.userInfo, 'app:s3cret');
      expect(t.databaseName, 'shop');

      // An explicit directConnection is the user's.
      final kept =
          MongoUri.tryParse('mongodb://h1,h2/db?directConnection=false')!
              .forTunnel('127.0.0.1', 1);
      expect(kept.params['directConnection'], 'false');

      expect(
        () => MongoUri.tryParse('mongodb+srv://u:p@c.example/db')!
            .forTunnel('127.0.0.1', 1),
        throwsUnsupportedError,
      );
    });
  });

  group('MongoConnection with a replica-set string', () {
    MongoConnection connection({String? uri}) => MongoConnection(
          id: 0,
          name: 'rs',
          host: 'db1.example',
          connectionString: uri ?? replicaSet,
        );

    test('the database of the string is the effective one', () {
      expect(connection().effectiveDatabase, 'shop');
    });

    test('opening another database keeps the seeds and sets the path', () {
      final u = connection().buildUriForDatabase('reports');
      final parsed = MongoUri.tryParse(u)!;
      expect(parsed.hosts, ['db1.example:27017', 'db2.example:27018']);
      expect(parsed.databaseName, 'reports');
      expect(parsed.params['replicaSet'], 'rs0');
      expect(parsed.params['authSource'], 'admin');
    });

    test('authSource defaults to the database the user was made in', () {
      final u = connection(
        uri: 'mongodb://app:pw@h1:27017,h2:27017/shop?replicaSet=rs0',
      ).buildUriForDatabase('reports');
      expect(MongoUri.tryParse(u)!.params['authSource'], 'shop');
    });

    test('through a tunnel the string becomes the local endpoint', () {
      final u = connection().buildConnectionUri(
        hostOverride: '127.0.0.1',
        portOverride: 50111,
      );
      final parsed = MongoUri.tryParse(u)!;
      expect(parsed.hosts, ['127.0.0.1:50111']);
      expect(parsed.params['directConnection'], 'true');
    });

    test('a tunnel with an SRV string is refused with an explanation', () {
      final c = connection(uri: 'mongodb+srv://u:p@cluster0.example/db');
      expect(
        () => c.buildConnectionUri(hostOverride: '127.0.0.1', portOverride: 1),
        throwsA(isA<UnsupportedError>().having(
            (e) => e.message, 'message', contains('mongodb+srv'))),
      );
    });
  });

  test('certificate paths are found in a host-list string', () {
    final paths = extractSslCertificatePathsFromString(
      'mongodb://h1:27017,h2:27017/db?sslrootcert=%2Fetc%2Fca.pem',
    );
    expect(paths.rootCert, '/etc/ca.pem');
  });
}
