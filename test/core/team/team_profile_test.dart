import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/team/team_profile.dart';

void main() {
  const row = ConnectionRow(
    type: 'postgres',
    name: 'Prod',
    host: 'db.example.com',
    port: 5432,
    username: 'alice',
    password: 'hunter2-secret',
    databaseName: 'app',
    useSSL: true,
    connectionString:
        'postgres://alice:hunter2-secret@db.example.com:5432/app?sslmode=require&password=hunter2-secret',
    driverOptions:
        '{"ssh_tunnel":{"host":"bastion","passphrase":"topsecret","port":22},"apiToken":"tok"}',
    createdAt: '2026-01-01T00:00:00',
  );

  test('export never contains secrets', () {
    final text = TeamProfileCodec.encode([row]);
    expect(text, isNot(contains('hunter2')));
    expect(text, isNot(contains('topsecret')));
    expect(text, isNot(contains('tok"')));
    expect(text, contains('db.example.com'));
    expect(text, contains('bastion'));
    expect(text, contains('sslmode=require'));
  });

  test('round trip keeps connection settings, drops password', () {
    final rows = TeamProfileCodec.decode(TeamProfileCodec.encode([row]));
    expect(rows.length, 1);
    final r = rows.single;
    expect(r.name, 'Prod');
    expect(r.host, 'db.example.com');
    expect(r.port, 5432);
    expect(r.username, 'alice');
    expect(r.databaseName, 'app');
    expect(r.useSSL, isTrue);
    expect(r.password, isNull);
    expect(r.id, isNull);
    expect(r.connectionString, isNot(contains('hunter2')));
  });

  test('import re-scrubs hand edited secrets', () {
    final doc = jsonEncode({
      'format': 'querya-team-profile',
      'version': 1,
      'connections': [
        {
          'type': 'mysql',
          'name': 'x',
          'connectionString': 'mysql://u:pw123@h/db',
          'driverOptions': '{"password":"pw123","a":1}',
        },
      ],
    });
    final r = TeamProfileCodec.decode(doc).single;
    expect(r.connectionString, isNot(contains('pw123')));
    expect(r.driverOptions, isNot(contains('pw123')));
    expect(r.driverOptions, contains('"a":1'));
  });

  test('rejects foreign or newer files', () {
    expect(() => TeamProfileCodec.decode('nope'),
        throwsA(isA<TeamProfileFormatException>()));
    expect(() => TeamProfileCodec.decode('{"format":"other"}'),
        throwsA(isA<TeamProfileFormatException>()));
    expect(
        () => TeamProfileCodec.decode(
            '{"format":"querya-team-profile","version":99,"connections":[]}'),
        throwsA(isA<TeamProfileFormatException>()));
  });

  test('skips malformed entries', () {
    final doc = jsonEncode({
      'format': 'querya-team-profile',
      'version': 1,
      'connections': [
        {'type': 'redis'},
        'junk',
        {'type': 'redis', 'name': 'ok'},
      ],
    });
    expect(TeamProfileCodec.decode(doc).map((r) => r.name), ['ok']);
  });

  group('secret keys (#1564)', () {
    test('export drops pwd, private keys, access keys, credentials and signatures',
        () {
      const noisy = ConnectionRow(
        type: 'postgres',
        name: 'Noisy',
        host: 'h',
        connectionString:
            'postgres://h:5432/d?db_pwd=s1&privateKey=s2&sslmode=require&authSource=admin',
        driverOptions:
            '{"pwd":"s3","private_key":"s4","accessKey":"s5","credentials":{"user":"u","x":"s6"},"signature":"s7","keep":"ok"}',
        createdAt: '2026-01-01T00:00:00',
      );
      final text = TeamProfileCodec.encode([noisy]);
      for (final secret in ['s1', 's2', 's3', 's4', 's5', 's6', 's7']) {
        expect(text, isNot(contains('"$secret"')), reason: secret);
        expect(text, isNot(contains('=$secret')), reason: secret);
      }
      expect(text, contains('sslmode=require'));
      expect(text, contains('authSource=admin'));
      expect(text, contains('keep'));
    });

    test('import scrubs the same keys from a hand-edited file', () {
      final doc = jsonEncode({
        'format': TeamProfileCodec.format,
        'version': TeamProfileCodec.version,
        'connections': [
          {
            'type': 'postgres',
            'name': 'Edited',
            'driverOptions': '{"privateKey":"s1","pwd":"s2","ok":1}',
          },
        ],
      });
      final r = TeamProfileCodec.decode(doc).single;
      expect(r.driverOptions, isNot(contains('s1')));
      expect(r.driverOptions, isNot(contains('s2')));
      expect(r.driverOptions, contains('"ok":1'));
    });
  });

  group('unreadable entries (#1564)', () {
    String profile(List<Object?> connections) => jsonEncode({
          'format': TeamProfileCodec.format,
          'version': TeamProfileCodec.version,
          'connections': connections,
        });

    test('a field of the wrong type skips the entry instead of throwing', () {
      final read = TeamProfileCodec.read(profile([
        {'type': 'postgres', 'name': 'good', 'host': 'h', 'port': 5432},
        {'type': 'postgres', 'name': 'port-as-text', 'port': '5432'},
        {'type': 'postgres', 'name': 'host-as-number', 'host': 5},
        {'type': 'postgres', 'name': 'user-as-list', 'username': ['a']},
        {'type': 'postgres', 'name': 'extension-as-map', 'extensionId': {}},
        {'type': 'postgres', 'name': 'url-as-number', 'connectionString': 7},
      ]));
      expect(read.rows.map((r) => r.name), ['good']);
      expect(read.skipped, 5);
    });

    test('entries without a type or name, or not objects, are counted', () {
      final read = TeamProfileCodec.read(profile([
        'text',
        42,
        {'name': 'no-type'},
        {'type': 'mysql', 'name': '   '},
        {'type': 'mysql', 'name': 'ok'},
      ]));
      expect(read.rows.map((r) => r.name), ['ok']);
      expect(read.skipped, 4);
    });

    test('null fields are fine; decode returns just the rows', () {
      final doc = profile([
        {'type': 'sqlite', 'name': 'local', 'host': null, 'port': null},
        {'type': 'sqlite', 'name': 'bad', 'port': 'x'},
      ]);
      expect(TeamProfileCodec.read(doc).skipped, 1);
      expect(TeamProfileCodec.decode(doc).map((r) => r.name), ['local']);
    });
  });
}
