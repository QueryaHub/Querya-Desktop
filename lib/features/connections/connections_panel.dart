import 'package:flutter/material.dart' as material show AlertDialog, BoxConstraints, BuildContext, Column, ConstrainedBox, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, Image, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, SystemMouseCursors, TextStyle, CustomScrollView, SliverToBoxAdapter, SliverFillRemaining, SliverPadding, GestureDetector, HitTestBehavior, SizedBox, AnimatedRotation, Row, BoxFit, Text, TextOverflow, Expanded, CircularProgressIndicator, Material, StatelessWidget, Colors, Tooltip, Color, LayoutBuilder, TextPainter, TextSpan, TextDirection, SelectableText, Padding, Widget, Navigator, ValueKey, FontWeight, VoidCallback, RepaintBoundary;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'package:querya_desktop/features/mongodb/mongo_database_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'new_folder_dialog.dart';

part 'connections_panel_sidebar.dart';
part 'connections_panel_redis.dart';
part 'connections_panel_mongo.dart';
part 'connections_panel_postgres_connection.dart';
part 'connections_panel_mysql.dart';
part 'connections_panel_pg_tree.dart';

/// Opens the PostgreSQL SQL tab; optional tree fields seed the editor for the
/// row that was right-clicked (left-click is not required).
typedef OnPostgresOpenSqlWorkspace = void Function(
  ConnectionRow connection, {
  String? database,
  String? schema,
  String? name,
  PostgresObjectKind? kind,
});

/// Left panel: Browser tree (pgAdmin-style). Uses shadcn layout widgets.
class ConnectionsPanel extends StatefulWidget {
  const ConnectionsPanel({
    super.key,
    this.selectedConnectionId,
    this.onConnectionSelected,
    this.onRedisDatabaseSelected,
    this.onMongoDBDatabaseSelected,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
    this.onMysqlObjectSelected,
    this.onMysqlOpenSqlWorkspace,
    /// When true, [initState] does not call [_loadData]. Widget tests that seed
    /// SQLite in setUp should call [ConnectionsPanelState.reloadConnectionsFromDb]
    /// inside [WidgetTester.runAsync] so only one load runs (avoids overlapping
    /// sqflite isolate futures clobbering state under FakeAsync).
    this.skipInitialDbLoadForTest = false,
  });

  /// Highlights the active connection row in the sidebar (workspace selection).
  final int? selectedConnectionId;

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
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;

  /// MySQL table or view selected in the tree.
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  )? onMysqlObjectSelected;

  /// Opens the MySQL workspace home and switches to the SQL tab.
  final void Function(ConnectionRow connection)? onMysqlOpenSqlWorkspace;

  final bool skipInitialDbLoadForTest;

  @override
  State<ConnectionsPanel> createState() => ConnectionsPanelState();
}

class ConnectionsPanelState extends State<ConnectionsPanel> {
  List<String> _folders = [];
  List<ConnectionRow> _connections = [];
  Map<String, int> _folderIdByName = {};
  final Set<String> _expandedFolders = {};
  /// Ignores stale [setState] when multiple [_loadData] runs overlap (e.g. tests).
  int _loadDataGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.skipInitialDbLoadForTest) {
      _loadData();
    }
  }

  /// Reloads folders and connections from [LocalDb] / [FoldersStorage].
  ///
  /// Widget tests should call this inside `WidgetTester.runAsync` so sqflite FFI
  /// futures complete outside the test's FakeAsync zone (otherwise [initState]'s
  /// [_loadData] may never reach [setState]).
  Future<void> reloadConnectionsFromDb() => _loadData();

  Future<void> _loadData() async {
    final gen = ++_loadDataGeneration;
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
    if (!mounted || gen != _loadDataGeneration) {
      return;
    }
    setState(() {
      final previousFolders = _folders.toSet();
      _folders = folders;
      _connections = connections;
      _folderIdByName = folderIdByName;
      for (final name in folders) {
        if (!previousFolders.contains(name)) {
          // First load (no folders in state yet): expand all — matches old UX.
          // Later, new folders stay collapsed so root connections stay visible
          // and the tree does not look like catalogs moved under the folder.
          if (previousFolders.isEmpty) {
            _expandedFolders.add(name);
          }
        }
      }
      _expandedFolders.removeWhere((n) => !folders.contains(n));
    });
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

  Future<void> _createConnection({
    int? folderId,
  }) async {
    final row = await promptCreateConnection(
      context,
      folderId: folderId,
    );
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
    final isSelected =
        widget.selectedConnectionId != null && widget.selectedConnectionId == conn.id;
    if (conn.type == 'postgresql') {
      return _PostgresConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onPostgresObjectSelected: widget.onPostgresObjectSelected,
        onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
      );
    } else if (conn.type == 'mysql') {
      return _MysqlConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onMysqlObjectSelected: widget.onMysqlObjectSelected,
        onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
      );
    } else if (conn.type == 'redis') {
      return _RedisConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onRedisDatabaseSelected?.call(conn, db),
      );
    } else if (conn.type == 'mongodb') {
      return _MongoConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: _iconForType(conn.type),
        iconAsset: _iconAssetForType(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onMongoDBDatabaseSelected?.call(conn, db),
      );
    }
    return _ConnectionTile(
      connection: conn,
      isSelected: isSelected,
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
            color: theme.colorScheme.border.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(20, 24, 16, 16),
            child: material.Text(
              'SERVERS',
              style: material.TextStyle(
                fontFamily: QueryaTypography.mono,
                fontSize: 11,
                letterSpacing: 0.85,
                fontWeight: material.FontWeight.w600,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.border.withValues(alpha: 0.22)),
          Expanded(
            child: material.RepaintBoundary(
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
                            initiallyExpanded: _expandedFolders.contains(name),
                            onExpansionCommitted: (folderName, expanded) {
                              if (expanded) {
                                _expandedFolders.add(folderName);
                              } else {
                                _expandedFolders.remove(folderName);
                              }
                            },
                            connections: _connections
                                .where((c) => c.folderId == _folderIdByName[name])
                                .toList(),
                            onRemove: () async {
                              await FoldersStorage.instance.remove(name);
                              await _loadData();
                            },
                            onNewConnection: (folderName) async {
                              final folderId =
                                  await LocalDb.instance.getFolderIdByName(folderName);
                              await _createConnection(folderId: folderId);
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
                              await Future.delayed(const Duration(milliseconds: 100));
                              if (!mounted) return;
                              await _createConnection();
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
          ),
        ],
      ),
    );
  }
}
