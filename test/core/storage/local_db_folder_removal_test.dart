import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import '../../support/local_db_test_support.dart';

/// `connections.folder_id` cascades on delete; removing a folder must not take
/// its connections, or their saved passwords, with it.
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

  test('removing a folder keeps its connections, now without a folder',
      () async {
    final db = LocalDb.instance;
    await db.addFolder('Team A');
    await db.addFolder('Team B');
    final a = await db.getFolderIdByName('Team A');
    final b = await db.getFolderIdByName('Team B');
    final inA = await db.addConnection(row('In A', folderId: a));
    final inB = await db.addConnection(row('In B', folderId: b));
    final root = await db.addConnection(row('Root'));
    await ConnectionSecretsStore.writeForConnection(inA, password: 'a-pw');

    await db.removeFolder('Team A');

    final byId = {for (final c in await db.getConnections()) c.id: c};
    expect(byId.keys, containsAll([inA, inB, root]));
    expect(byId[inA]!.folderId, isNull);
    expect(byId[inB]!.folderId, b, reason: 'another folder is untouched');
    expect(byId[root]!.folderId, isNull);
    expect(await db.getFolderIdByName('Team A'), isNull);
    expect((await ConnectionSecretsStore.readForConnection(inA)).password,
        'a-pw');
  });

  test('removing an empty or unknown folder is harmless', () async {
    final db = LocalDb.instance;
    await db.addFolder('Empty');
    await db.removeFolder('Empty');
    await db.removeFolder('Never existed');
    expect(await db.getFolderIdByName('Empty'), isNull);
  });

  test('setConnectionFolder moves a connection into a folder and out again',
      () async {
    final db = LocalDb.instance;
    await db.addFolder('Mover');
    final folder = await db.getFolderIdByName('Mover');
    final id = await db.addConnection(row('Movable'));
    await ConnectionSecretsStore.writeForConnection(id, password: 'mv-pw');

    await db.setConnectionFolder(id, folder);
    expect((await db.getConnectionById(id))!.folderId, folder);

    await db.setConnectionFolder(id, null);
    expect((await db.getConnectionById(id))!.folderId, isNull);
    expect((await ConnectionSecretsStore.readForConnection(id)).password,
        'mv-pw');
  });
}
