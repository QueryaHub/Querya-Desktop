import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/local_db_test_support.dart';

/// Removing a folder deletes the connections in it (foreign key cascade). Their
/// secrets are in the OS store, which the cascade does not reach.
void main() {
  late Directory dir;

  setUpAll(() async => dir = await initTestLocalDb('folder_removal_'));
  tearDownAll(() => disposeTestLocalDb(dir));

  ConnectionRow row(String name, {int? folderId}) => ConnectionRow(
        type: 'postgresql',
        name: name,
        host: 'db.example.com',
        port: 5432,
        folderId: folderId,
        createdAt: DateTime.utc(2026).toIso8601String(),
      );

  test('removing a folder deletes its connections and their secrets',
      () async {
    final db = LocalDb.instance;
    await db.addFolder('Doomed');
    final folderId = await db.getFolderIdByName('Doomed');
    final inside = await db.addConnection(row('Inside', folderId: folderId));
    final outside = await db.addConnection(row('Outside'));
    await ConnectionSecretsStore.writeForConnection(inside, password: 'in-pw');
    await ConnectionSecretsStore.writeForConnection(outside,
        password: 'out-pw');

    expect(await db.countConnectionsInFolder('Doomed'), 1);
    expect(await db.countConnectionsInFolder('Nowhere'), 0);

    await db.removeFolder('Doomed');

    final names = (await db.getConnections()).map((c) => c.name);
    expect(names, contains('Outside'));
    expect(names, isNot(contains('Inside')));
    expect((await ConnectionSecretsStore.readForConnection(inside)).password,
        anyOf(isNull, isEmpty));
    expect((await ConnectionSecretsStore.readForConnection(outside)).password,
        'out-pw');
  });
}
