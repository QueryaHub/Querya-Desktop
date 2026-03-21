import 'package:flutter/material.dart' as material show BuildContext, Widget, Padding, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, Image, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, SystemMouseCursors, DefaultTextStyle, TextStyle, CustomScrollView, SliverToBoxAdapter, SliverFillRemaining, SliverPadding, GestureDetector, HitTestBehavior, SizedBox, Column, AnimatedRotation, Row, BoxFit, Text, TextOverflow, Expanded, CircularProgressIndicator, Material, StatelessWidget, Colors;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'package:querya_desktop/features/mongodb/mongo_database_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';
import 'new_connection_dialog.dart';
import 'new_folder_dialog.dart';

/// Left panel: Browser tree (pgAdmin-style). Uses shadcn layout widgets.
class ConnectionsPanel extends StatefulWidget {
  const ConnectionsPanel({
    super.key,
    this.onConnectionSelected,
    this.onRedisDatabaseSelected,
    this.onMongoDBDatabaseSelected,
    this.onPostgresObjectSelected,
  });

  /// Called when the user taps a connection tile.
  final void Function(ConnectionRow connection)? onConnectionSelected;

  /// Called when the user taps a Redis database node in the tree.
  final void Function(ConnectionRow connection, int database)?
      onRedisDatabaseSelected;

  /// Called when the user taps a MongoDB database node in the tree.
  final void Function(ConnectionRow connection, String database)?
      onMongoDBDatabaseSelected;

  /// Called when the user taps a PostgreSQL table, view, function, or sequence.
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<ConnectionsPanel> createState() => _ConnectionsPanelState();
}

class _ConnectionsPanelState extends State<ConnectionsPanel> {
  List<String> _folders = [];
  List<ConnectionRow> _connections = [];
  Map<String, int> _folderIdByName = {};
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final folders = await FoldersStorage.instance.load();
    var connections = await LocalDb.instance.getConnections();
    // Remove stub connections (PostgreSQL/MySQL placeholders) from DB and from list
    for (final c in connections.where(_isStubConnection)) {
      if (c.id != null) await LocalDb.instance.removeConnection(c.id!);
    }
    connections = connections.where((c) => !_isStubConnection(c)).toList();
    final folderIdByName = <String, int>{};
    for (final name in folders) {
      final id = await LocalDb.instance.getFolderIdByName(name);
      if (id != null) folderIdByName[name] = id;
    }
    if (mounted) {
      setState(() {
        final previousFolders = _folders.toSet();
        _folders = folders;
        _connections = connections;
        _folderIdByName = folderIdByName;
        for (final name in folders) {
          if (!previousFolders.contains(name)) _expandedFolders.add(name);
        }
        _expandedFolders.removeWhere((n) => !folders.contains(n));
      });
    }
  }

  static bool _isStubConnection(ConnectionRow c) {
    return c.type == 'mysql' && c.name == 'MySQL connection';
  }

  Future<void> _createFolder(BuildContext menuContext) async {
    final name = await showNewFolderDialog(menuContext);
    if (name == null || !mounted) return;
    await FoldersStorage.instance.add(name);
    if (mounted) setState(() => _folders = FoldersStorage.instance.folders);
  }

  Future<void> _createConnection(ConnectionType type, {int? folderId}) async {
    ConnectionRow? row;

    if (type == ConnectionType.postgresql) {
      row = await showPostgresConnectionForm(context, folderId: folderId);
    } else if (type == ConnectionType.mongodb) {
      row = await showMongoConnectionForm(context, folderId: folderId);
    } else if (type == ConnectionType.redis) {
      row = await showRedisConnectionForm(context, folderId: folderId);
    } else {
      row = null;
    }

    if (row != null && mounted) {
      await LocalDb.instance.addConnection(row);
      await _loadData();
    }
  }

  Future<void> _removeConnection(int id) async {
    await LocalDb.instance.removeConnection(id);
    await _loadData();
  }

  /// Icon for a connection type (matches New Connection dialog).
  material.IconData _iconForType(String type) {
    return switch (type) {
      'mongodb' => material.Icons.eco_rounded,
      'postgresql' => material.Icons.storage_rounded,
      'mysql' => material.Icons.table_chart_rounded,
      'redis' => material.Icons.memory_rounded,
      _ => material.Icons.settings_ethernet_rounded,
    };
  }

  /// Asset path for connection type logo (null = use icon).
  static String? _iconAssetForType(String type) {
    return switch (type) {
      'postgresql' => 'assets/images/postgresql_icon.png',
      'mysql' => 'assets/images/mysql_icon.png',
      'redis' => 'assets/images/redis_icon.png',
      'mongodb' => 'assets/images/mongodb_icon.png',
      _ => null,
    };
  }

  Widget _buildConnectionTile(ConnectionRow conn) {
    if (conn.type == 'postgresql') {
      return _PostgresConnectionTile(
        connection: conn,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onPostgresObjectSelected: widget.onPostgresObjectSelected,
      );
    } else if (conn.type == 'redis') {
      return _RedisConnectionTile(
        connection: conn,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onRedisDatabaseSelected?.call(conn, db),
      );
    } else if (conn.type == 'mongodb') {
      return _MongoConnectionTile(
        connection: conn,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onMongoDBDatabaseSelected?.call(conn, db),
      );
    }
    return _ConnectionTile(
      connection: conn,
      icon: _iconForType(conn.type),
      iconAsset: _iconAssetForType(conn.type),
      onRemove: () => _removeConnection(conn.id!),
      onTap: () => widget.onConnectionSelected?.call(conn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Connections without a folder
    final rootConnections = _connections.where((c) => c.folderId == null).toList();

    return material.Container(
      decoration: material.BoxDecoration(
        color: theme.colorScheme.background,
        border: material.Border(
          right: material.BorderSide(
            color: theme.colorScheme.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(20, 24, 16, 16),
            child: material.DefaultTextStyle(
              style: material.TextStyle(color: theme.colorScheme.mutedForeground),
                  child: const Text('Browser').semiBold().small(),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.border.withValues(alpha: 0.3)),
          Expanded(
            child: material.CustomScrollView(
              slivers: [
                material.SliverPadding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  sliver: material.SliverToBoxAdapter(
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        // Folders
                        for (final name in _folders)
                          _FolderTile(
                            name: name,
                            isExpanded: _expandedFolders.contains(name),
                            onToggle: () {
                              setState(() {
                                if (_expandedFolders.contains(name)) {
                                  _expandedFolders.remove(name);
                                } else {
                                  _expandedFolders.add(name);
                                }
                              });
                            },
                            connections: _connections
                                .where((c) => c.folderId == _folderIdByName[name])
                                .toList(),
                            onRemove: () async {
                              await FoldersStorage.instance.remove(name);
                              await _loadData();
                            },
                            onNewConnection: (folderName) async {
                              final type = await showNewConnectionDialog(context);
                              if (type == null || !mounted) return;
                              final folderId = await LocalDb.instance.getFolderIdByName(folderName);
                              await _createConnection(type, folderId: folderId);
                            },
                            iconForType: _iconForType,
                            onRemoveConnection: _removeConnection,
                            onConnectionTap: widget.onConnectionSelected,
                            onRedisDatabaseTap: widget.onRedisDatabaseSelected,
                            onMongoDBDatabaseTap: widget.onMongoDBDatabaseSelected,
                            buildConnectionTile: _buildConnectionTile,
                          ),
                        // Root connections (no folder)
                        for (final conn in rootConnections)
                          _buildConnectionTile(conn),
                        // Empty state
                        if (_connections.isEmpty && _folders.isEmpty)
                          const material.Padding(
                            padding: material.EdgeInsets.only(top: 8),
                            child: _EmptyState(message: 'No connections yet'),
                          ),
                      ],
                    ),
                  ),
                ),
                material.SliverFillRemaining(
                  hasScrollBody: false,
                  child: ContextMenu(
                    items: [
                      MenuButton(
                        leading: material.Icon(material.Icons.add_rounded, size: 18, color: theme.colorScheme.mutedForeground),
                        subMenu: [
                          MenuButton(
                            leading: material.Icon(material.Icons.settings_ethernet_rounded, size: 18, color: theme.colorScheme.mutedForeground),
                            onPressed: (menuContext) async {
                              final type = await showNewConnectionDialog(menuContext);
                              if (type == null || !mounted) return;
                              await Future.delayed(const Duration(milliseconds: 100));
                              if (!mounted) return;
                              await _createConnection(type);
                            },
                            child: const Text('New Connection'),
                          ),
                          MenuButton(
                            leading: material.Icon(material.Icons.folder_rounded, size: 18, color: theme.colorScheme.mutedForeground),
                            onPressed: (menuContext) => _createFolder(menuContext),
                            child: const Text('New Folder'),
                          ),
                        ],
                        child: const Text('Create'),
                      ),
                    ],
                    child: material.GestureDetector(
                      behavior: material.HitTestBehavior.opaque,
                      child: const material.SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.25),
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          material.Icon(
            material.Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.mutedForeground,
          ),
          const Gap(10),
          Expanded(
            child: Text(message).muted().small(),
          ),
        ],
      ),
    );
  }
}

/// Tile for a single connection in the sidebar.
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
  });

  final ConnectionRow connection;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = iconAsset != null
        ? material.Image.asset(
            iconAsset!,
            width: 16,
            height: 16,
            fit: material.BoxFit.contain,
            errorBuilder: (_, __, ___) => material.Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          )
        : material.Icon(icon, size: 16, color: theme.colorScheme.primary);
    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => onRemove(),
          child: const Text('Remove connection'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(bottom: 2),
        child: material.MouseRegion(
          cursor: material.SystemMouseCursors.click,
          child: material.InkWell(
            onTap: onTap,
            borderRadius: material.BorderRadius.circular(6),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: material.Row(
                children: [
                  iconWidget,
                  const Gap(8),
                  material.Expanded(
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Text(
                          connection.name,
                          overflow: material.TextOverflow.ellipsis,
                          maxLines: 1,
                          style: material.TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.foreground,
                          ),
                        ),
                        if (connection.host != null)
                          material.Text(
                            '${connection.host}:${connection.port ?? ''}',
                            overflow: material.TextOverflow.ellipsis,
                            maxLines: 1,
                            style: material.TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.name,
    required this.isExpanded,
    required this.onToggle,
    required this.connections,
    required this.onRemove,
    required this.onNewConnection,
    required this.iconForType,
    required this.onRemoveConnection,
    this.onConnectionTap,
    this.onRedisDatabaseTap,
    this.onMongoDBDatabaseTap,
    this.buildConnectionTile,
  });

  final String name;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<ConnectionRow> connections;
  final VoidCallback onRemove;
  final void Function(String folderName) onNewConnection;
  final material.IconData Function(String type) iconForType;
  final Future<void> Function(int id) onRemoveConnection;
  final void Function(ConnectionRow connection)? onConnectionTap;
  final void Function(ConnectionRow connection, int database)? onRedisDatabaseTap;
  final void Function(ConnectionRow connection, String database)? onMongoDBDatabaseTap;
  final Widget Function(ConnectionRow conn)? buildConnectionTile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.settings_ethernet_rounded, size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (menuContext) => onNewConnection(name),
          child: const Text('New connection'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => onRemove(),
          child: const Text('Remove folder'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(bottom: 4),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.MouseRegion(
              cursor: material.SystemMouseCursors.click,
              child: material.InkWell(
                onTap: onToggle,
                borderRadius: material.BorderRadius.circular(6),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: material.Row(
                    children: [
                      material.AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: material.Icon(
                          material.Icons.chevron_right_rounded,
                          size: 18,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                      const Gap(2),
                      material.Icon(material.Icons.folder_rounded, size: 18, color: theme.colorScheme.primary),
                      const Gap(8),
                      material.Expanded(
                        child: material.Text(
                          name,
                          overflow: material.TextOverflow.ellipsis,
                          maxLines: 1,
                          style: material.TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Show connections inside this folder when expanded
            if (isExpanded)
              for (final conn in connections)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 24),
                  child: buildConnectionTile != null
                      ? buildConnectionTile!(conn)
                      : _ConnectionTile(
                          connection: conn,
                          icon: iconForType(conn.type),
                          iconAsset: _ConnectionsPanelState._iconAssetForType(conn.type),
                          onRemove: () => onRemoveConnection(conn.id!),
                          onTap: () => onConnectionTap?.call(conn),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}

// ─── Redis connection tile with expandable database tree ────────────────────

class _RedisConnectionTile extends StatefulWidget {
  const _RedisConnectionTile({
    required this.connection,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onDatabaseTap,
  });

  final ConnectionRow connection;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(int database)? onDatabaseTap;

  @override
  State<_RedisConnectionTile> createState() => _RedisConnectionTileState();
}

class _RedisConnectionTileState extends State<_RedisConnectionTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  // All 16 databases (db0–db15) with key counts
  List<({int index, int keys})> _databases = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _databases.isEmpty && !_loading) {
      _loadDatabases();
    }
  }

  Future<void> _loadDatabases() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Use a temporary connection so we don't kill the main view's connection.
      final c = widget.connection;
      final conn = RedisConnection(
        id: -1,
        name: 'sidebar_probe',
        host: c.host ?? 'localhost',
        port: c.port ?? 6379,
        username: c.username,
        password: c.password,
      );
      await conn.connect();
      final raw = await conn.info();
      await conn.disconnect();

      final info = parseRedisInfo(raw);
      final keyspace = info['Keyspace'] ?? {};

      // Build all 16 databases with their key counts
      final dbs = <({int index, int keys})>[];
      for (var i = 0; i < 16; i++) {
        final dbKey = 'db$i';
        final dbInfo = keyspace[dbKey];
        int keys = 0;
        if (dbInfo != null) {
          for (final part in dbInfo.split(',')) {
            final kv = part.split('=');
            if (kv.length == 2 && kv[0].trim() == 'keys') {
              keys = int.tryParse(kv[1].trim()) ?? 0;
            }
          }
        }
        dbs.add((index: i, keys: keys));
      }

      if (!mounted) return;
      setState(() {
        _databases = dbs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = widget.iconAsset != null
        ? material.Image.asset(
            widget.iconAsset!,
            width: 16,
            height: 16,
            fit: material.BoxFit.contain,
            errorBuilder: (_, __, ___) => material.Icon(
              widget.icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          )
        : material.Icon(widget.icon, size: 16, color: theme.colorScheme.primary);

    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.refresh_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) {
            _databases = [];
            _loadDatabases();
          },
          child: const Text('Refresh databases'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => widget.onRemove(),
          child: const Text('Remove connection'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(bottom: 2),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            // Connection row
            material.Row(
              children: [
                // Expand/collapse arrow
                material.MouseRegion(
                  cursor: material.SystemMouseCursors.click,
                  child: material.InkWell(
                    onTap: _toggle,
                    borderRadius: material.BorderRadius.circular(4),
                    child: material.Padding(
                      padding: const material.EdgeInsets.all(2),
                      child: material.AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: material.Icon(
                          material.Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
                // Connection name — clickable for stats
                material.Expanded(
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.InkWell(
                      onTap: widget.onTap,
                      borderRadius: material.BorderRadius.circular(6),
                      child: material.Padding(
                        padding: const material.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: material.Row(
                          children: [
                            iconWidget,
                            const Gap(8),
                            material.Expanded(
                              child: material.Column(
                                crossAxisAlignment:
                                    material.CrossAxisAlignment.start,
                                mainAxisSize: material.MainAxisSize.min,
                                children: [
                                  material.Text(
                                    widget.connection.name,
                                    overflow: material.TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: material.TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.foreground,
                                    ),
                                  ),
                                  if (widget.connection.host != null)
                                    material.Text(
                                      '${widget.connection.host}:${widget.connection.port ?? ''}',
                                      overflow: material.TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: material.TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.mutedForeground,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Expanded database children — ALL 16 databases
            if (_expanded) ...[
              if (_loading)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Row(
                    children: [
                      const material.SizedBox(
                        width: 12,
                        height: 12,
                        child: material.CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const Gap(8),
                      const Text('Loading...').muted().xSmall(),
                    ],
                  ),
                ),
              if (_error != null)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Text(
                    'Error',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                        fontSize: 11, color: theme.colorScheme.destructive),
                  ),
                ),
              for (final db in _databases)
                _RedisDatabaseNode(
                  index: db.index,
                  keys: db.keys,
                  onTap: () => widget.onDatabaseTap?.call(db.index),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RedisDatabaseNode extends StatelessWidget {
  const _RedisDatabaseNode({
    required this.index,
    required this.keys,
    required this.onTap,
  });

  final int index;
  final int keys;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 24),
      child: material.MouseRegion(
        cursor: material.SystemMouseCursors.click,
        child: material.InkWell(
          onTap: onTap,
          borderRadius: material.BorderRadius.circular(6),
          child: material.Padding(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: material.Row(
              children: [
                material.Icon(
                  material.Icons.dns_rounded,
                  size: 14,
                  color: keys > 0
                      ? theme.colorScheme.primary.withValues(alpha: 0.7)
                      : theme.colorScheme.mutedForeground.withValues(alpha: 0.5),
                ),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    'db$index',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                      fontSize: 12,
                      color: keys > 0
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                if (keys > 0)
                  material.Text(
                    '$keys',
                    style: material.TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.mutedForeground),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── MongoDB connection tile with expandable database tree ──────────────────

class _MongoConnectionTile extends StatefulWidget {
  const _MongoConnectionTile({
    required this.connection,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onDatabaseTap,
  });

  final ConnectionRow connection;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(String database)? onDatabaseTap;

  @override
  State<_MongoConnectionTile> createState() => _MongoConnectionTileState();
}

class _MongoConnectionTileState extends State<_MongoConnectionTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _databases = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _databases.isEmpty && !_loading) {
      _loadDatabases();
    }
  }

  Future<void> _loadDatabases() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = widget.connection;
      final conn = MongoConnection(
        id: -1,
        name: 'sidebar_probe',
        host: c.host ?? 'localhost',
        port: c.port ?? 27017,
        username: c.username,
        password: c.password,
        database: c.databaseName,
        authSource: c.authSource,
        useSSL: c.useSSL,
        connectionString: c.connectionString,
      );
      await conn.connect();
      final dbs = await conn.listDatabases();
      await conn.disconnect();

      if (!mounted) return;
      setState(() {
        _databases = dbs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createDatabase() async {
    final dbName = await showCreateMongoDBDialog(context);
    if (dbName == null || !mounted) return;
    _databases = [];
    await _loadDatabases();
  }

  Future<void> _deleteDatabase(String dbName) async {
    if (!mounted) return;
    try {
      final c = widget.connection;
      final conn = MongoConnection(
        id: -1,
        name: 'sidebar_probe',
        host: c.host ?? 'localhost',
        port: c.port ?? 27017,
        username: c.username,
        password: c.password,
        database: c.databaseName,
        authSource: c.authSource,
        useSSL: c.useSSL,
        connectionString: c.connectionString,
      );
      await conn.connect();
      await conn.dropDatabase(dbName);
      await conn.disconnect();

      if (mounted) {
        _databases = [];
        await _loadDatabases();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = widget.iconAsset != null
        ? material.Image.asset(
            widget.iconAsset!,
            width: 16,
            height: 16,
            fit: material.BoxFit.contain,
            errorBuilder: (_, __, ___) => material.Icon(
              widget.icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          )
        : material.Icon(widget.icon, size: 16, color: theme.colorScheme.primary);

    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.add_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => _createDatabase(),
          child: const Text('Create database'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.refresh_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) {
            _databases = [];
            _loadDatabases();
          },
          child: const Text('Refresh databases'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => widget.onRemove(),
          child: const Text('Remove connection'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(bottom: 2),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            // Connection row
            material.Row(
              children: [
                // Expand/collapse arrow
                material.MouseRegion(
                  cursor: material.SystemMouseCursors.click,
                  child: material.InkWell(
                    onTap: _toggle,
                    borderRadius: material.BorderRadius.circular(4),
                    child: material.Padding(
                      padding: const material.EdgeInsets.all(2),
                      child: material.AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: material.Icon(
                          material.Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
                // Connection name — clickable for stats
                material.Expanded(
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.InkWell(
                      onTap: widget.onTap,
                      borderRadius: material.BorderRadius.circular(6),
                      child: material.Padding(
                        padding: const material.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: material.Row(
                          children: [
                            iconWidget,
                            const Gap(8),
                            material.Expanded(
                              child: material.Column(
                                crossAxisAlignment:
                                    material.CrossAxisAlignment.start,
                                mainAxisSize: material.MainAxisSize.min,
                                children: [
                                  material.Text(
                                    widget.connection.name,
                                    overflow: material.TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: material.TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.foreground,
                                    ),
                                  ),
                                  if (widget.connection.host != null)
                                    material.Text(
                                      '${widget.connection.host}:${widget.connection.port ?? ''}',
                                      overflow: material.TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: material.TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.mutedForeground,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Expanded database children
            if (_expanded) ...[
              if (_loading)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Row(
                    children: [
                      const material.SizedBox(
                        width: 12,
                        height: 12,
                        child: material.CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const Gap(8),
                      const Text('Loading...').muted().xSmall(),
                    ],
                  ),
                ),
              if (_error != null)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Text(
                    'Error',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                        fontSize: 11, color: theme.colorScheme.destructive),
                  ),
                ),
              for (final db in _databases)
                _MongoDatabaseNode(
                  name: db,
                  onTap: () => widget.onDatabaseTap?.call(db),
                  onDelete: () => _deleteDatabase(db),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MongoDatabaseNode extends StatelessWidget {
  const _MongoDatabaseNode({
    required this.name,
    required this.onTap,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => onDelete(),
          child: const Text('Delete database'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(left: 24),
        child: material.MouseRegion(
          cursor: material.SystemMouseCursors.click,
          child: material.InkWell(
            onTap: onTap,
            borderRadius: material.BorderRadius.circular(6),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5),
              child: material.Row(
                children: [
                  material.Icon(
                    material.Icons.storage_rounded,
                    size: 14,
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                  ),
                  const Gap(8),
                  material.Expanded(
                    child: material.Text(
                      name,
                      overflow: material.TextOverflow.ellipsis,
                      maxLines: 1,
                      style: material.TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── PostgreSQL connection tile with expandable database tree ────────────────

class _PostgresConnectionTile extends StatefulWidget {
  const _PostgresConnectionTile({
    required this.connection,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<_PostgresConnectionTile> createState() =>
      _PostgresConnectionTileState();
}

class _PostgresConnectionTileState extends State<_PostgresConnectionTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _databases = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _databases.isEmpty && !_loading) {
      _loadDatabases();
    }
  }

  Future<void> _loadDatabases() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: c.databaseName ?? 'postgres',
        mode: PgSessionMode.readOnly,
      );
      final dbs = await lease.connection.listDatabases();

      if (!mounted) return;
      setState(() {
        _databases = dbs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      lease?.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = widget.iconAsset != null
        ? material.Image.asset(
            widget.iconAsset!,
            width: 16,
            height: 16,
            fit: material.BoxFit.contain,
            errorBuilder: (_, __, ___) => material.Icon(
              widget.icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          )
        : material.Icon(widget.icon, size: 16, color: theme.colorScheme.primary);

    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.refresh_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) {
            _databases = [];
            _loadDatabases();
          },
          child: const Text('Refresh databases'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => widget.onRemove(),
          child: const Text('Remove connection'),
        ),
      ],
      child: material.Padding(
        padding: const material.EdgeInsets.only(bottom: 2),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Row(
              children: [
                material.MouseRegion(
                  cursor: material.SystemMouseCursors.click,
                  child: material.InkWell(
                    onTap: _toggle,
                    borderRadius: material.BorderRadius.circular(4),
                    child: material.Padding(
                      padding: const material.EdgeInsets.all(2),
                      child: material.AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: material.Icon(
                          material.Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
                material.Expanded(
                  child: material.MouseRegion(
                    cursor: material.SystemMouseCursors.click,
                    child: material.InkWell(
                      onTap: widget.onTap,
                      borderRadius: material.BorderRadius.circular(6),
                      child: material.Padding(
                        padding: const material.EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: material.Row(
                          children: [
                            iconWidget,
                            const Gap(8),
                            material.Expanded(
                              child: material.Column(
                                crossAxisAlignment:
                                    material.CrossAxisAlignment.start,
                                mainAxisSize: material.MainAxisSize.min,
                                children: [
                                  material.Text(
                                    widget.connection.name,
                                    overflow: material.TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: material.TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.foreground,
                                    ),
                                  ),
                                  if (widget.connection.host != null)
                                    material.Text(
                                      '${widget.connection.host}:${widget.connection.port ?? ''}',
                                      overflow: material.TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: material.TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.mutedForeground,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              if (_loading)
                material.Padding(
                  padding:
                      const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Row(
                    children: [
                      const material.SizedBox(
                        width: 12,
                        height: 12,
                        child:
                            material.CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const Gap(8),
                      const Text('Loading...').muted().xSmall(),
                    ],
                  ),
                ),
              if (_error != null)
                material.Padding(
                  padding:
                      const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Text(
                    'Error',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                        fontSize: 11, color: theme.colorScheme.destructive),
                  ),
                ),
              if (_databases.isNotEmpty)
                _PgDatabasesNode(
                  connection: widget.connection,
                  databases: _databases,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PgDatabasesNode extends StatefulWidget {
  const _PgDatabasesNode({
    required this.connection,
    required this.databases,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final List<String> databases;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<_PgDatabasesNode> createState() => _PgDatabasesNodeState();
}

class _PgDatabasesNodeState extends State<_PgDatabasesNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 20),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: material.Row(
                  children: [
                    material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const Gap(4),
                    material.Icon(material.Icons.dns_rounded,
                        size: 14,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                    const Gap(6),
                    material.Expanded(
                      child: material.Text(
                        'Databases (${widget.databases.length})',
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            for (final db in widget.databases)
              _PgDatabaseNode(
                connection: widget.connection,
                databaseName: db,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
        ],
      ),
    );
  }
}

class _PgDatabaseNode extends StatefulWidget {
  const _PgDatabaseNode({
    required this.connection,
    required this.databaseName,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final String databaseName;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<_PgDatabaseNode> createState() => _PgDatabaseNodeState();
}

class _PgDatabaseNodeState extends State<_PgDatabaseNode> {
  bool _expanded = false;
  bool _loading = false;
  List<String> _schemas = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _schemas.isEmpty && !_loading) {
      _loadSchemas();
    }
  }

  Future<void> _loadSchemas() async {
    if (!mounted) return;
    setState(() => _loading = true);
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: widget.databaseName,
        mode: PgSessionMode.readOnly,
      );
      final schemas = await lease.connection.listSchemas();
      if (!mounted) return;
      setState(() {
        _schemas = schemas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      lease?.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.InkWell(
              onTap: _toggle,
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: material.Row(
                  children: [
                    material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const Gap(4),
                    material.Icon(material.Icons.storage_rounded,
                        size: 14,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                    const Gap(6),
                    material.Expanded(
                      child: material.Text(
                        widget.databaseName,
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Extensions',
              icon: material.Icons.extension_rounded,
              kind: PostgresObjectKind.databaseExtensions,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
            ),
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Foreign data',
              icon: material.Icons.public_rounded,
              kind: PostgresObjectKind.databaseForeignData,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
            ),
            if (_loading)
              material.Padding(
                padding:
                    const material.EdgeInsets.only(left: 24, top: 2, bottom: 2),
                child: material.Row(
                  children: [
                    const material.SizedBox(
                      width: 10,
                      height: 10,
                      child:
                          material.CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const Gap(6),
                    const Text('Loading...').muted().xSmall(),
                  ],
                ),
              ),
            if (_schemas.isNotEmpty)
              _PgSchemasNode(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemas: _schemas,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
          ],
        ],
      ),
    );
  }
}

class _PgDbToolRow extends material.StatelessWidget {
  const _PgDbToolRow({
    required this.connection,
    required this.databaseName,
    required this.label,
    required this.icon,
    required this.kind,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String label;
  final material.IconData icon;
  final PostgresObjectKind kind;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 12, top: 2, bottom: 2),
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          borderRadius: material.BorderRadius.circular(4),
          onTap: onPostgresObjectSelected == null
              ? null
              : () => onPostgresObjectSelected!(
                    connection,
                    databaseName,
                    '',
                    '',
                    kind,
                  ),
          child: material.Padding(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: material.Row(
              children: [
                material.Icon(icon,
                    size: 14,
                    color: theme.colorScheme.primary.withValues(alpha: 0.85)),
                const Gap(6),
                material.Expanded(
                  child: Text(label).small(),
                ),
                material.Icon(
                  material.Icons.chevron_right_rounded,
                  size: 14,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PgSchemasNode extends StatefulWidget {
  const _PgSchemasNode({
    required this.connection,
    required this.databaseName,
    required this.schemas,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final String databaseName;
  final List<String> schemas;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<_PgSchemasNode> createState() => _PgSchemasNodeState();
}

class _PgSchemasNodeState extends State<_PgSchemasNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: material.Row(
                  children: [
                    material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const Gap(4),
                    material.Icon(material.Icons.account_tree_rounded,
                        size: 13, color: theme.colorScheme.mutedForeground),
                    const Gap(6),
                    material.Expanded(
                      child: material.Text(
                        'Schemas (${widget.schemas.length})',
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            for (final schema in widget.schemas)
              _PgSchemaNode(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: schema,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
        ],
      ),
    );
  }
}

class _PgSchemaNode extends StatefulWidget {
  const _PgSchemaNode({
    required this.connection,
    required this.databaseName,
    required this.schemaName,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String schemaName;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  State<_PgSchemaNode> createState() => _PgSchemaNodeState();
}

class _PgSchemaNodeState extends State<_PgSchemaNode> {
  bool _expanded = false;
  bool _loading = false;
  List<String> _tables = [];
  List<String> _views = [];
  List<String> _matviews = [];
  List<String> _functions = [];
  List<String> _sequences = [];
  bool _loaded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && !_loaded && !_loading) {
      _loadObjects();
    }
  }

  Future<void> _loadObjects() async {
    if (!mounted) return;
    setState(() => _loading = true);
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: widget.databaseName,
        mode: PgSessionMode.readOnly,
      );
      final conn = lease.connection;
      final tables = await conn.listTables(schema: widget.schemaName);
      final views = await conn.listViews(schema: widget.schemaName);
      List<String> matviews = [];
      try {
        matviews =
            await conn.listMaterializedViews(schema: widget.schemaName);
      } catch (_) {
        // pg_matviews / permissions may fail on some servers; keep tree usable.
      }
      final functions = await conn.listFunctions(schema: widget.schemaName);
      final sequences = await conn.listSequences(schema: widget.schemaName);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _views = views;
        _matviews = matviews;
        _functions = functions;
        _sequences = sequences;
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      lease?.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 12),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.InkWell(
              onTap: _toggle,
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: material.Row(
                  children: [
                    material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const Gap(4),
                    material.Icon(material.Icons.diamond_outlined,
                        size: 13,
                        color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                    const Gap(6),
                    material.Expanded(
                      child: material.Text(
                        widget.schemaName,
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                            fontSize: 12, color: theme.colorScheme.foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            if (_loading)
              material.Padding(
                padding:
                    const material.EdgeInsets.only(left: 24, top: 2, bottom: 2),
                child: material.Row(
                  children: [
                    const material.SizedBox(
                      width: 10,
                      height: 10,
                      child:
                          material.CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const Gap(6),
                    const Text('Loading...').muted().xSmall(),
                  ],
                ),
              ),
            if (_loaded) ...[
              _PgObjectGroup(
                label: 'Tables',
                icon: material.Icons.table_chart_rounded,
                items: _tables,
                onItemTap: widget.onPostgresObjectSelected != null
                    ? (name) => widget.onPostgresObjectSelected!(
                          widget.connection,
                          widget.databaseName,
                          widget.schemaName,
                          name,
                          PostgresObjectKind.table,
                        )
                    : null,
              ),
              _PgObjectGroup(
                label: 'Views',
                icon: material.Icons.view_agenda_rounded,
                items: _views,
                onItemTap: widget.onPostgresObjectSelected != null
                    ? (name) => widget.onPostgresObjectSelected!(
                          widget.connection,
                          widget.databaseName,
                          widget.schemaName,
                          name,
                          PostgresObjectKind.view,
                        )
                    : null,
              ),
              _PgObjectGroup(
                label: 'Materialized views',
                icon: material.Icons.dynamic_feed_rounded,
                items: _matviews,
                onItemTap: widget.onPostgresObjectSelected != null
                    ? (name) => widget.onPostgresObjectSelected!(
                          widget.connection,
                          widget.databaseName,
                          widget.schemaName,
                          name,
                          PostgresObjectKind.materializedView,
                        )
                    : null,
              ),
              _PgObjectGroup(
                label: 'Functions',
                icon: material.Icons.functions_rounded,
                items: _functions,
                onItemTap: widget.onPostgresObjectSelected != null
                    ? (name) => widget.onPostgresObjectSelected!(
                          widget.connection,
                          widget.databaseName,
                          widget.schemaName,
                          name,
                          PostgresObjectKind.function,
                        )
                    : null,
              ),
              _PgObjectGroup(
                label: 'Sequences',
                icon: material.Icons.format_list_numbered_rounded,
                items: _sequences,
                onItemTap: widget.onPostgresObjectSelected != null
                    ? (name) => widget.onPostgresObjectSelected!(
                          widget.connection,
                          widget.databaseName,
                          widget.schemaName,
                          name,
                          PostgresObjectKind.sequence,
                        )
                    : null,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Indexes',
                icon: material.Icons.table_rows_rounded,
                kind: PostgresObjectKind.schemaIndexes,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Triggers',
                icon: material.Icons.bolt_rounded,
                kind: PostgresObjectKind.schemaTriggers,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Types',
                icon: material.Icons.category_rounded,
                kind: PostgresObjectKind.schemaTypes,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PgSchemaToolRow extends material.StatelessWidget {
  const _PgSchemaToolRow({
    required this.connection,
    required this.databaseName,
    required this.schemaName,
    required this.label,
    required this.icon,
    required this.kind,
    this.onPostgresObjectSelected,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String schemaName;
  final String label;
  final material.IconData icon;
  final PostgresObjectKind kind;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          borderRadius: material.BorderRadius.circular(4),
          onTap: onPostgresObjectSelected == null
              ? null
              : () => onPostgresObjectSelected!(
                    connection,
                    databaseName,
                    schemaName,
                    '',
                    kind,
                  ),
          child: material.Padding(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: material.Row(
              children: [
                material.Icon(icon,
                    size: 13, color: theme.colorScheme.mutedForeground),
                const Gap(6),
                material.Expanded(
                  child: Text(label).muted().xSmall(),
                ),
                material.Icon(
                  material.Icons.chevron_right_rounded,
                  size: 13,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PgObjectGroup extends StatefulWidget {
  const _PgObjectGroup({
    required this.label,
    required this.icon,
    required this.items,
    this.onItemTap,
  });

  final String label;
  final material.IconData icon;
  final List<String> items;
  final void Function(String itemName)? onItemTap;

  @override
  State<_PgObjectGroup> createState() => _PgObjectGroupState();
}

class _PgObjectGroupState extends State<_PgObjectGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: material.BorderRadius.circular(4),
              child: material.Padding(
                padding:
                    const material.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: material.Row(
                  children: [
                    material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 13,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const Gap(4),
                    material.Icon(widget.icon,
                        size: 13, color: theme.colorScheme.mutedForeground),
                    const Gap(6),
                    material.Expanded(
                      child: material.Text(
                        '${widget.label} (${widget.items.length})',
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            for (final item in widget.items)
              material.Padding(
                padding: const material.EdgeInsets.only(left: 22),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  child: material.MouseRegion(
                    cursor: widget.onItemTap != null
                        ? material.SystemMouseCursors.click
                        : material.SystemMouseCursors.basic,
                    child: material.InkWell(
                      onTap: widget.onItemTap != null
                          ? () => widget.onItemTap!(item)
                          : null,
                      borderRadius: material.BorderRadius.circular(4),
                      child: material.Row(
                        children: [
                          material.Icon(widget.icon,
                              size: 12,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.5)),
                          const Gap(6),
                          material.Expanded(
                            child: material.Text(
                              item,
                              overflow: material.TextOverflow.ellipsis,
                              maxLines: 1,
                              style: material.TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
