import 'package:flutter/material.dart' as material
    show
        AlertDialog,
        BoxConstraints,
        BuildContext,
        Column,
        ConstrainedBox,
        Container,
        BoxDecoration,
        Border,
        BorderSide,
        InkWell,
        Icon,
        Icons,
        IconData,
        Image,
        EdgeInsets,
        EdgeInsetsGeometry,
        BorderRadius,
        CrossAxisAlignment,
        MainAxisSize,
        MouseRegion,
        SystemMouseCursors,
        TextStyle,
        CustomScrollView,
        SliverFillRemaining,
        SliverPadding,
        SliverList,
        SliverChildBuilderDelegate,
        GestureDetector,
        HitTestBehavior,
        SizedBox,
        AnimatedRotation,
        Row,
        BoxFit,
        Text,
        TextOverflow,
        Expanded,
        CircularProgressIndicator,
        Material,
        StatelessWidget,
        Colors,
        Tooltip,
        Color,
        SelectableText,
        Padding,
        Widget,
        Navigator,
        ValueKey,
        FontWeight,
        VoidCallback,
        RepaintBoundary,
        ListView,
        ClampingScrollPhysics;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_builder.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/core/motion/querya_animated_expand.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/features/connections/connection_creation_flow.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/app/app_shutdown.dart';

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
part 'connections_panel_sqlite.dart';
part 'connections_panel_extension.dart';

/// Opens the PostgreSQL SQL tab; optional tree fields seed the editor for the
/// row that was right-clicked (left-click is not required).
typedef OnPostgresOpenSqlWorkspace = void Function(
  ConnectionRow connection, {
  String? database,
  String? schema,
  String? name,
  PostgresObjectKind? kind,
});

/// Typical height of a compact tree row (object leaf / table name).
const double kConnectionTreeRowExtent = 28;

/// Build all rows inline when the list is short.
const int kConnectionTreeEagerThreshold = 24;

/// Max rows visible before nested list scrolls (virtualized via [ListView.builder]).
const int kConnectionTreeMaxVisibleRows = 14;

/// Builds a short [Column] or a height-capped [ListView.builder] for large lists.
material.Widget lazyConnectionTreeList({
  required material.BuildContext context,
  required int itemCount,
  required material.Widget Function(material.BuildContext context, int index)
      itemBuilder,
  double? itemExtent,
  int eagerThreshold = kConnectionTreeEagerThreshold,
  int maxVisibleRows = kConnectionTreeMaxVisibleRows,
  material.EdgeInsetsGeometry? padding,
}) {
  if (itemCount == 0) {
    return const material.SizedBox.shrink();
  }
  if (itemCount <= eagerThreshold) {
    return material.Column(
      mainAxisSize: material.MainAxisSize.min,
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itemCount; i++) itemBuilder(context, i),
      ],
    );
  }
  final rowExtent = itemExtent ?? kConnectionTreeRowExtent;
  return material.ConstrainedBox(
    constraints: material.BoxConstraints(
      maxHeight: maxVisibleRows * rowExtent,
    ),
    child: material.ListView.builder(
      padding: padding ?? material.EdgeInsets.zero,
      shrinkWrap: true,
      physics: const material.ClampingScrollPhysics(),
      itemCount: itemCount,
      itemExtent: itemExtent,
      itemBuilder: itemBuilder,
    ),
  );
}

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
    this.onSqliteObjectSelected,
    this.onSqliteOpenSqlWorkspace,
    this.onExtensionObjectSelected,

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

  /// SQLite table or view selected in the tree.
  final void Function(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  )? onSqliteObjectSelected;

  /// Opens the SQLite workspace home and switches to the SQL tab.
  final void Function(ConnectionRow connection)? onSqliteOpenSqlWorkspace;

  /// Fires when a table/view node is clicked in an extension driver tree.
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
  )? onExtensionObjectSelected;

  final bool skipInitialDbLoadForTest;

  @override
  State<ConnectionsPanel> createState() => ConnectionsPanelState();
}

class ConnectionsPanelState extends State<ConnectionsPanel> {
  List<String> _folders = [];
  List<ConnectionRow> _connections = [];
  Map<String, int> _folderIdByName = {};
  final Set<String> _expandedFolders = {};
  final Set<int> _expandedConnections = {};

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
    await ExtensionDriverSession.instance.disconnect(id);
    SqliteService.instance.interrupt(
      ConnectionRow(id: id, type: 'sqlite', name: '', createdAt: ''),
      mode: SqliteSessionMode.readOnly,
    );
    SqliteService.instance.interrupt(
      ConnectionRow(id: id, type: 'sqlite', name: '', createdAt: ''),
      mode: SqliteSessionMode.readWrite,
    );
    await LocalDb.instance.removeConnection(id);
    await _loadData();
  }

  void connect(int connectionId) {
    setState(() {
      _expandedConnections.add(connectionId);
    });
  }

  @visibleForTesting
  bool isConnectionExpanded(int id) => _expandedConnections.contains(id);

  Future<void> disconnect(ConnectionRow conn) async {
    final id = conn.id!;
    setState(() {
      _expandedConnections.remove(id);
    });
    if (conn.type == 'postgresql') {
      PostgresService.instance.interrupt(conn, database: conn.databaseName ?? 'postgres', mode: PgSessionMode.readOnly);
      PostgresService.instance.interrupt(conn, database: conn.databaseName ?? 'postgres', mode: PgSessionMode.readWrite);
    } else if (conn.type == 'mysql') {
      MysqlService.instance.interrupt(conn, database: conn.databaseName ?? '', mode: MysqlSessionMode.readOnly);
      MysqlService.instance.interrupt(conn, database: conn.databaseName ?? '', mode: MysqlSessionMode.readWrite);
    } else if (conn.type == 'sqlite') {
      SqliteService.instance.interrupt(conn, mode: SqliteSessionMode.readOnly);
      SqliteService.instance.interrupt(conn, mode: SqliteSessionMode.readWrite);
    } else if (conn.type == 'redis') {
      final redisConn = RedisService.instance.getConnection(id);
      if (redisConn != null) {
        await RedisService.instance.disconnect(redisConn);
      }
    } else if (conn.type == 'mongodb') {
      await MongoService.instance.disconnectByConnectionId(id);
    }
    if (ExtensionDriverCatalog.isExtensionDriverConnection(conn)) {
      await ExtensionDriverSession.instance.disconnect(id);
    }
  }

  Future<void> disconnectAll() async {
    setState(() {
      _expandedConnections.clear();
    });
    await disconnectAllExternalServices();
  }

  Future<void> disconnectOthers(ConnectionRow keepConn) async {
    final keepId = keepConn.id!;
    setState(() {
      _expandedConnections.clear();
      _expandedConnections.add(keepId);
    });
    for (final conn in _connections) {
      if (conn.id == keepId) continue;
      await disconnect(conn);
    }
  }

  Future<void> reconnect(ConnectionRow conn) async {
    final id = conn.id!;
    await disconnect(conn);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      connect(id);
    }
  }

  Widget _buildConnectionTile(ConnectionRow conn) {
    final isSelected = widget.selectedConnectionId != null &&
        widget.selectedConnectionId == conn.id;
    final isExpanded = _expandedConnections.contains(conn.id);
    void handleExpandedChanged(bool expanded) {
      setState(() {
        if (expanded) {
          _expandedConnections.add(conn.id!);
        } else {
          _expandedConnections.remove(conn.id!);
        }
      });
    }

    if (conn.type == 'postgresql') {
      return _PostgresConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onPostgresObjectSelected: widget.onPostgresObjectSelected,
        onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    } else if (conn.type == 'mysql') {
      return _MysqlConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onMysqlObjectSelected: widget.onMysqlObjectSelected,
        onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    } else if (conn.type == 'redis') {
      return _RedisConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onRedisDatabaseSelected?.call(conn, db),
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    } else if (conn.type == 'mongodb') {
      return _MongoConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onDatabaseTap: (db) => widget.onMongoDBDatabaseSelected?.call(conn, db),
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    } else if (conn.type == 'sqlite') {
      return _SqliteConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onSqliteObjectSelected: widget.onSqliteObjectSelected,
        onSqliteOpenSqlWorkspace: widget.onSqliteOpenSqlWorkspace,
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    } else if (ExtensionDriverCatalog.isExtensionDriverConnection(conn)) {
      return _ExtensionConnectionTile(
        connection: conn,
        isSelected: isSelected,
        icon: QueryaIcons.connectionIcon(conn.type),
        iconAsset: QueryaIcons.connectionAsset(conn.type),
        onRemove: () => _removeConnection(conn.id!),
        onTap: () => widget.onConnectionSelected?.call(conn),
        onObjectSelected: widget.onExtensionObjectSelected,
        isExpanded: isExpanded,
        onExpandedChanged: handleExpandedChanged,
      );
    }
    return _ConnectionTile(
      connection: conn,
      isSelected: isSelected,
      icon: QueryaIcons.connectionIcon(conn.type),
      iconAsset: QueryaIcons.connectionAsset(conn.type),
      onRemove: () => _removeConnection(conn.id!),
      onTap: () => widget.onConnectionSelected?.call(conn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Connections without a folder
    final rootConnections =
        _connections.where((c) => c.folderId == null).toList();
    final showEmptyState = _connections.isEmpty && _folders.isEmpty;
    final topLevelCount =
        _folders.length + rootConnections.length + (showEmptyState ? 1 : 0);

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
          Divider(
              height: 1,
              color: theme.colorScheme.border.withValues(alpha: 0.22)),
          Expanded(
            child: material.RepaintBoundary(
              child: material.CustomScrollView(
                slivers: [
                  material.SliverPadding(
                    padding: const material.EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    sliver: material.SliverList(
                      delegate: material.SliverChildBuilderDelegate(
                        (context, index) {
                          if (showEmptyState && index == 0) {
                            return const material.Padding(
                              padding: material.EdgeInsets.only(top: 8),
                              child: _EmptyState(message: 'No connections yet'),
                            );
                          }
                          final folderOffset = showEmptyState ? 1 : 0;
                          final folderIndex = index - folderOffset;
                          if (folderIndex < _folders.length) {
                            final name = _folders[folderIndex];
                            return _FolderTile(
                              name: name,
                              initiallyExpanded:
                                  _expandedFolders.contains(name),
                              onExpansionCommitted: (folderName, expanded) {
                                if (expanded) {
                                  _expandedFolders.add(folderName);
                                } else {
                                  _expandedFolders.remove(folderName);
                                }
                              },
                              connections: _connections
                                  .where((c) =>
                                      c.folderId == _folderIdByName[name])
                                  .toList(),
                              onRemove: () async {
                                await FoldersStorage.instance.remove(name);
                                await _loadData();
                              },
                              onNewConnection: (folderName) async {
                                final folderId = await LocalDb.instance
                                    .getFolderIdByName(folderName);
                                await _createConnection(folderId: folderId);
                              },
                              iconForType: QueryaIcons.connectionIcon,
                              onRemoveConnection: _removeConnection,
                              onConnectionTap: widget.onConnectionSelected,
                              onRedisDatabaseTap:
                                  widget.onRedisDatabaseSelected,
                              onMongoDBDatabaseTap:
                                  widget.onMongoDBDatabaseSelected,
                              buildConnectionTile: _buildConnectionTile,
                            );
                          }
                          final connIndex = folderIndex - _folders.length;
                          return _buildConnectionTile(
                              rootConnections[connIndex]);
                        },
                        childCount: topLevelCount,
                      ),
                    ),
                  ),
                  material.SliverFillRemaining(
                    hasScrollBody: false,
                    child: ContextMenu(
                      items: [
                        MenuButton(
                          leading: material.Icon(material.Icons.add_rounded,
                              size: 18,
                              color: theme.colorScheme.mutedForeground),
                          subMenu: [
                            MenuButton(
                              leading: material.Icon(
                                  material.Icons.settings_ethernet_rounded,
                                  size: 18,
                                  color: theme.colorScheme.mutedForeground),
                              onPressed: (menuContext) async {
                                await Future.delayed(
                                    const Duration(milliseconds: 100));
                                if (!mounted) return;
                                await _createConnection();
                              },
                              child: const Text('New Connection'),
                            ),
                            MenuButton(
                              leading: material.Icon(
                                  material.Icons.folder_rounded,
                                  size: 18,
                                  color: theme.colorScheme.mutedForeground),
                              onPressed: (menuContext) =>
                                  _createFolder(menuContext),
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
