import 'package:flutter/material.dart' as material show AlertDialog, BoxConstraints, BuildContext, Column, ConstrainedBox, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, Image, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, SystemMouseCursors, DefaultTextStyle, TextStyle, CustomScrollView, SliverToBoxAdapter, SliverFillRemaining, SliverPadding, GestureDetector, HitTestBehavior, SizedBox, AnimatedRotation, Row, BoxFit, Text, TextOverflow, Expanded, CircularProgressIndicator, Material, StatelessWidget, Colors, Tooltip, Color, LayoutBuilder, TextPainter, TextSpan, TextDirection, SelectableText, Padding, Widget, Navigator;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/database/mongodb_service.dart';
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
    this.onPostgresOpenSqlWorkspace,
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

  /// Opens the PostgreSQL workspace home and switches to the SQL tab (e.g. from tree context menu).
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

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
    await MongoService.instance.disconnectByConnectionId(id);
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
        onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
          material.Expanded(
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
      final conn = await MongoService.instance.ensureConnected(widget.connection);
      final dbs = await conn.listDatabases();

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
    final ok = await showAppDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => material.AlertDialog(
        title: const Text('Drop database?'),
        content: Text(
          'Permanently delete database "$dbName"? This cannot be undone.',
        ),
        actions: [
          OutlineButton(
            onPressed: () => material.Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => material.Navigator.of(ctx).pop(true),
            child: const Text('Drop database'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final conn = await MongoService.instance.ensureConnected(widget.connection);
      await conn.dropDatabase(dbName);

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
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4, right: 8),
                  child: material.ConstrainedBox(
                    constraints: const material.BoxConstraints(maxWidth: double.infinity),
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      mainAxisSize: material.MainAxisSize.min,
                      children: [
                        material.Row(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Icon(
                              material.Icons.error_outline_rounded,
                              size: 14,
                              color: theme.colorScheme.destructive,
                            ),
                            const Gap(6),
                            material.Expanded(
                              child: material.Text(
                                'Could not load databases',
                                maxLines: 2,
                                overflow: material.TextOverflow.ellipsis,
                                style: material.TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.destructive,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Gap(6),
                        material.SelectableText(
                          _error!,
                          style: material.TextStyle(
                            fontSize: 10,
                            height: 1.35,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final db in _databases)
                _MongoDatabaseNode(
                  connection: widget.connection,
                  name: db,
                  onTap: () => widget.onDatabaseTap?.call(db),
                  onDelete: () => _deleteDatabase(db),
                  onRefreshDatabases: () {
                    setState(() => _databases = []);
                    _loadDatabases();
                  },
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
    required this.connection,
    required this.name,
    required this.onTap,
    required this.onDelete,
    required this.onRefreshDatabases,
  });

  final ConnectionRow connection;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRefreshDatabases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: _PgTreeRow(
        label: name,
        icon: material.Icons.storage_rounded,
        iconSize: 13,
        iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
        textStyle: material.TextStyle(
          fontSize: 12,
          color: theme.colorScheme.foreground,
        ),
        verticalPadding: 3,
        onTap: onTap,
        connection: connection,
        onContextRefresh: onRefreshDatabases,
        onOpenSqlWorkspace: null,
        onContextDelete: onDelete,
        contextDeleteLabel: 'Delete database',
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
    this.onPostgresOpenSqlWorkspace,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

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
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                  onRefreshDatabases: () {
                    setState(() => _databases = []);
                    _loadDatabases();
                  },
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
    this.onPostgresOpenSqlWorkspace,
    required this.onRefreshDatabases,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
  final VoidCallback onRefreshDatabases;

  @override
  State<_PgDatabasesNode> createState() => _PgDatabasesNodeState();
}

/// Ellipsis label; tooltip only when text overflows (intrinsic width > slot).
class _PgTreeRowLabel extends material.StatelessWidget {
  const _PgTreeRowLabel({
    required this.label,
    required this.textStyle,
  });

  final String label;
  final material.TextStyle textStyle;

  @override
  material.Widget build(material.BuildContext context) {
    return material.LayoutBuilder(
      builder: (context, constraints) {
        final tp = material.TextPainter(
          text: material.TextSpan(text: label, style: textStyle),
          maxLines: 1,
          textDirection: material.TextDirection.ltr,
        );
        tp.layout(maxWidth: double.infinity);
        final overflow = tp.width > constraints.maxWidth + 0.5;
        final text = material.Text(
          label,
          overflow: material.TextOverflow.ellipsis,
          maxLines: 1,
          style: textStyle,
        );
        if (!overflow) return text;
        return material.Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 450),
          child: text,
        );
      },
    );
  }
}

/// Shared tree row: consistent ink hover, optional context menu, tooltips when truncated.
class _PgTreeRow extends material.StatelessWidget {
  const _PgTreeRow({
    required this.label,
    this.leading,
    this.icon,
    this.iconSize = 13,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.verticalPadding = 3,
    required this.textStyle,
    this.connection,
    this.onContextRefresh,
    this.onOpenSqlWorkspace,
    this.onContextDelete,
    this.contextDeleteLabel,
  });

  final String label;
  final material.Widget? leading;
  final material.IconData? icon;
  final double iconSize;
  final material.Color? iconColor;
  final material.Widget? trailing;
  final void Function()? onTap;
  final double verticalPadding;
  final material.TextStyle textStyle;
  final ConnectionRow? connection;
  final VoidCallback? onContextRefresh;
  final void Function(ConnectionRow connection)? onOpenSqlWorkspace;
  final VoidCallback? onContextDelete;
  final String? contextDeleteLabel;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final row = material.Material(
      color: material.Colors.transparent,
      child: material.InkWell(
        onTap: onTap,
        borderRadius: material.BorderRadius.circular(4),
        hoverColor: primary.withValues(alpha: 0.07),
        splashColor: primary.withValues(alpha: 0.10),
        highlightColor: primary.withValues(alpha: 0.05),
        mouseCursor: onTap != null
            ? material.SystemMouseCursors.click
            : material.SystemMouseCursors.basic,
        child: material.Padding(
          padding: material.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: verticalPadding,
          ),
          child: material.Row(
            children: [
              if (leading != null) ...[
                leading!,
                const Gap(4),
              ],
              if (icon != null) ...[
                material.Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? muted,
                ),
                const Gap(6),
              ],
              material.Expanded(
                child: _PgTreeRowLabel(label: label, textStyle: textStyle),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
    if (connection == null) return row;
    return ContextMenu(
      items: [
        if (onContextRefresh != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.refresh_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onContextRefresh!(),
            child: const Text('Refresh'),
          ),
        MenuButton(
          leading: material.Icon(
            material.Icons.copy_rounded,
            size: 18,
            color: theme.colorScheme.mutedForeground,
          ),
          onPressed: (_) {
            Clipboard.setData(ClipboardData(text: label));
          },
          child: const Text('Copy name'),
        ),
        if (onOpenSqlWorkspace != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onOpenSqlWorkspace!(connection!),
            child: const Text('Open in SQL'),
          ),
        if (onContextDelete != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.delete_outline_rounded,
              size: 18,
              color: theme.colorScheme.destructive,
            ),
            onPressed: (_) => onContextDelete!(),
            child: Text(contextDeleteLabel ?? 'Delete'),
          ),
      ],
      child: row,
    );
  }
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
          _PgTreeRow(
            label: 'Databases (${widget.databases.length})',
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.dns_rounded,
            iconSize: 14,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshDatabases,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final db in widget.databases)
              _PgDatabaseNode(
                connection: widget.connection,
                databaseName: db,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
    this.onPostgresOpenSqlWorkspace,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

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
          _PgTreeRow(
            label: widget.databaseName,
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.storage_rounded,
            iconSize: 14,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            onTap: _toggle,
            connection: widget.connection,
            onContextRefresh: _loadSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded) ...[
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Extensions',
              icon: material.Icons.extension_rounded,
              kind: PostgresObjectKind.databaseExtensions,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
              onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
              onContextRefresh: _loadSchemas,
            ),
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Foreign data',
              icon: material.Icons.public_rounded,
              kind: PostgresObjectKind.databaseForeignData,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
              onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
              onContextRefresh: _loadSchemas,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefreshSchemas: _loadSchemas,
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
    this.onPostgresOpenSqlWorkspace,
    this.onContextRefresh,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
  final VoidCallback? onContextRefresh;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.mutedForeground;
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: _PgTreeRow(
        label: label,
        icon: icon,
        iconSize: 13,
        iconColor: muted,
        trailing: material.Icon(
          material.Icons.chevron_right_rounded,
          size: 13,
          color: muted,
        ),
        onTap: onPostgresObjectSelected == null
            ? null
            : () => onPostgresObjectSelected!(
                  connection,
                  databaseName,
                  '',
                  '',
                  kind,
                ),
        textStyle: material.TextStyle(
          fontSize: 11,
          color: muted,
        ),
        connection: connection,
        onContextRefresh: onContextRefresh,
        onOpenSqlWorkspace: onPostgresOpenSqlWorkspace,
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
    this.onPostgresOpenSqlWorkspace,
    required this.onRefreshSchemas,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
  final VoidCallback onRefreshSchemas;

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
          _PgTreeRow(
            label: 'Schemas (${widget.schemas.length})',
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.account_tree_rounded,
            iconSize: 13,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final schema in widget.schemas)
              _PgSchemaNode(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: schema,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
    this.onPostgresOpenSqlWorkspace,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

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
          _PgTreeRow(
            label: widget.schemaName,
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.diamond_outlined,
            iconSize: 13,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.6),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            onTap: _toggle,
            connection: widget.connection,
            onContextRefresh: _loadObjects,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
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
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
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
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
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
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
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
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Triggers',
                icon: material.Icons.bolt_rounded,
                kind: PostgresObjectKind.schemaTriggers,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Types',
                icon: material.Icons.category_rounded,
                kind: PostgresObjectKind.schemaTypes,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
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
    this.onPostgresOpenSqlWorkspace,
    this.onContextRefresh,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
  final VoidCallback? onContextRefresh;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.mutedForeground;
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: _PgTreeRow(
        label: label,
        icon: icon,
        iconSize: 13,
        iconColor: muted,
        trailing: material.Icon(
          material.Icons.chevron_right_rounded,
          size: 13,
          color: muted,
        ),
        onTap: onPostgresObjectSelected == null
            ? null
            : () => onPostgresObjectSelected!(
                  connection,
                  databaseName,
                  schemaName,
                  '',
                  kind,
                ),
        textStyle: material.TextStyle(
          fontSize: 11,
          color: muted,
        ),
        connection: connection,
        onContextRefresh: onContextRefresh,
        onOpenSqlWorkspace: onPostgresOpenSqlWorkspace,
      ),
    );
  }
}

class _PgObjectGroup extends StatefulWidget {
  const _PgObjectGroup({
    required this.connection,
    required this.onRefresh,
    required this.label,
    required this.icon,
    required this.items,
    this.onPostgresOpenSqlWorkspace,
    this.onItemTap,
  });

  final ConnectionRow connection;
  final VoidCallback onRefresh;
  final String label;
  final material.IconData icon;
  final List<String> items;
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
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
          _PgTreeRow(
            label: '${widget.label} (${widget.items.length})',
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: widget.icon,
            iconSize: 13,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefresh,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final item in widget.items)
              material.Padding(
                padding: const material.EdgeInsets.only(left: 22),
                child: _PgTreeRow(
                  label: item,
                  icon: widget.icon,
                  iconSize: 12,
                  iconColor:
                      theme.colorScheme.primary.withValues(alpha: 0.5),
                  textStyle: material.TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.foreground,
                  ),
                  verticalPadding: 2,
                  onTap: widget.onItemTap != null
                      ? () => widget.onItemTap!(item)
                      : null,
                  connection: widget.connection,
                  onContextRefresh: widget.onRefresh,
                  onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                ),
              ),
        ],
      ),
    );
  }
}
