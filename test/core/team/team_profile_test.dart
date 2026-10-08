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
}
