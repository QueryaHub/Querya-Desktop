import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';

/// Saved connections: rows, secrets and SSH configuration kept in step.
/// Part of [LocalDb], which keeps the same methods and delegates here.
class ConnectionRepository {
  ConnectionRepository(this._open, {this.onRemoved});

  final Future<Database> Function() _open;

  /// Told the id of each connection removed, for state kept elsewhere.
  final void Function(int id)? onRemoved;

  /// Returns all saved connections.
  ///
  /// By default, passwords and connection strings are NOT eagerly hydrated from
  /// the platform secure store to avoid IPC bottlenecks, Keychain lockups, and
  /// D-Bus timeouts during sidebar/startup population. Secrets are resolved
  /// on-demand when a connection is initiated.
  Future<List<ConnectionRow>> getConnections(
      {bool hydrateSecrets = false}) async {
    final db = await _open();
    final rows =
        await db.query('connections', orderBy: 'sort_order ASC, name ASC');
    if (!hydrateSecrets) {
      return rows.map((m) => ConnectionRow.fromMap(m)).toList();
    }
    final futures =
        rows.map((m) => _hydrateConnection(ConnectionRow.fromMap(m)));
    return Future.wait(futures);
  }

  static Future<ConnectionRow> _hydrateConnection(ConnectionRow row) async {
    if (row.id == null) return row;
    try {
      final secrets = await ConnectionSecretsStore.readForConnection(row.id!);
      return row.copyWith(
        password: secrets.password ?? row.password,
        connectionString: secrets.connectionString ?? row.connectionString,
      );
    } catch (e) {
      debugPrint(
          'LocalDb._hydrateConnection failed for connection ${row.id}: $e');
      return row;
    }
  }

  /// Hydrates secrets for a single [ConnectionRow] on demand.
  Future<ConnectionRow> hydrateConnection(ConnectionRow row) =>
      _hydrateConnection(row);

  /// Retrieves a single connection by [id], optionally hydrating secrets.
  Future<ConnectionRow?> getConnectionById(int id,
      {bool hydrateSecrets = false}) async {
    final db = await _open();
    final rows =
        await db.query('connections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = ConnectionRow.fromMap(rows.first);
    if (!hydrateSecrets) return row;
    return _hydrateConnection(row);
  }

  /// Inserts a row and returns the SQLite row id.
  /// Password and connection string are stored in the OS secure store, not in SQLite.
  ///
  /// If writing secrets fails, the SQLite row is rolled back and the error is
  /// rethrown so callers can surface a Keychain / libsecret failure.
  Future<int> addConnection(ConnectionRow row) async {
    final db = await _open();
    final id = await db.insert('connections', row.toPersistenceMap());
    try {
      await ConnectionSecretsStore.writeForConnection(
        id,
        password: row.password,
        connectionString: row.connectionString,
      );
      if (row.sshSecrets != null) {
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          id,
          password: row.sshSecrets!.password,
          privateKey: row.sshSecrets!.privateKey,
          passphrase: row.sshSecrets!.passphrase,
          jumpPassword: row.sshSecrets!.jumpPassword,
        );
      }
    } catch (e) {
      try {
        await ConnectionSecretsStore.deleteForConnection(id);
      } catch (_) {
        // Best-effort cleanup of any partial secret writes.
      }
      await db.delete('connections', where: 'id = ?', whereArgs: [id]);
      rethrow;
    }
    return id;
  }

  /// Updates an existing connection row in SQLite and its secrets in the secure store.
  ///
  /// If writing secrets fails, the previous SQLite row and previous secrets are
  /// restored (best effort) and the error is rethrown.
  Future<void> updateConnection(ConnectionRow row) async {
    if (row.id == null) {
      throw ArgumentError(
          'ConnectionRow.id cannot be null when calling updateConnection');
    }
    final db = await _open();
    final previousMaps = await db.query(
      'connections',
      where: 'id = ?',
      whereArgs: [row.id],
    );
    if (previousMaps.isEmpty) {
      throw ArgumentError('No connection found with id ${row.id}');
    }
    final previousRow = ConnectionRow.fromMap(previousMaps.first);
    final previousSecrets =
        await ConnectionSecretsStore.readForConnection(row.id!);
    final previousSsh =
        await ConnectionSecretsStore.readSshSecretsForConnection(row.id!);

    await db.transaction((txn) async {
      final count = await txn.update(
        'connections',
        row.toPersistenceMap(),
        where: 'id = ?',
        whereArgs: [row.id],
      );
      if (count == 0) {
        throw ArgumentError('No connection found with id ${row.id}');
      }
    });

    try {
      await ConnectionSecretsStore.writeForConnection(
        row.id!,
        password: row.password,
        connectionString: row.connectionString,
      );
      if (row.sshSecrets != null) {
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          row.id!,
          password: row.sshSecrets!.password,
          privateKey: row.sshSecrets!.privateKey,
          passphrase: row.sshSecrets!.passphrase,
          jumpPassword: row.sshSecrets!.jumpPassword,
        );
      } else if (row.sshTunnelConfig?.enabled != true) {
        // The tunnel was turned off: its password and key do not stay in the
        // keyring (#1311).
        await ConnectionSecretsStore.writeSshSecretsForConnection(row.id!);
      }
    } catch (e) {
      await db.update(
        'connections',
        previousRow.toPersistenceMap(),
        where: 'id = ?',
        whereArgs: [row.id],
      );
      try {
        await ConnectionSecretsStore.writeForConnection(
          row.id!,
          password: previousSecrets.password,
          connectionString: previousSecrets.connectionString,
        );
        // The SSH secrets may be half written too (four keys, one by one).
        await ConnectionSecretsStore.writeSshSecretsForConnection(
          row.id!,
          password: previousSsh.password,
          privateKey: previousSsh.privateKey,
          passphrase: previousSsh.passphrase,
          jumpPassword: previousSsh.jumpPassword,
        );
      } catch (_) {
        // Best-effort restore of previous secrets; surface the original error.
      }
      rethrow;
    }
  }

  /// Deletes a connection. SQLite deletion always proceeds even if the secure
  /// store delete fails (e.g. missing key or unavailable libsecret daemon).
  Future<void> removeConnection(int id) async {
    onRemoved?.call(id);
    try {
      await ConnectionSecretsStore.deleteForConnection(id);
    } catch (_) {
      // Do not block removing the connection metadata when the OS store fails.
    }
    final db = await _open();
    await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }
}
