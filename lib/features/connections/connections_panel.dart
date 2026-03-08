import 'package:flutter/material.dart' as material show Padding, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, Image, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, SystemMouseCursors, DefaultTextStyle, TextStyle, CustomScrollView, SliverToBoxAdapter, SliverFillRemaining, SliverPadding, GestureDetector, HitTestBehavior, SizedBox, Column, AnimatedRotation, Row, BoxFit, Text, TextOverflow, Expanded;
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';
import 'new_connection_dialog.dart';
import 'new_folder_dialog.dart';

/// Left panel: Browser tree (pgAdmin-style). Uses shadcn layout widgets.
class ConnectionsPanel extends StatefulWidget {
  const ConnectionsPanel({
    super.key,
    this.onConnectionSelected,
  });

  /// Called when the user taps a connection tile.
  final void Function(ConnectionRow connection)? onConnectionSelected;

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
    return (c.type == 'postgresql' && c.name == 'PostgreSQL connection') ||
        (c.type == 'mysql' && c.name == 'MySQL connection');
  }

  Future<void> _createFolder(BuildContext menuContext) async {
    final name = await showNewFolderDialog(menuContext);
    if (name == null || !mounted) return;
    await FoldersStorage.instance.add(name);
    if (mounted) setState(() => _folders = FoldersStorage.instance.folders);
  }

  Future<void> _createConnection(ConnectionType type, {int? folderId}) async {
    ConnectionRow? row;

    if (type == ConnectionType.mongodb) {
      row = await showMongoConnectionForm(context, folderId: folderId);
    } else if (type == ConnectionType.redis) {
      row = await showRedisConnectionForm(context, folderId: folderId);
    } else {
      // PostgreSQL / MySQL: no connection form yet — do not create a stub
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
                          ),
                        // Root connections (no folder)
                        for (final conn in rootConnections)
                          _ConnectionTile(
                            connection: conn,
                            icon: _iconForType(conn.type),
                            iconAsset: _iconAssetForType(conn.type),
                            onRemove: () => _removeConnection(conn.id!),
                            onTap: () => widget.onConnectionSelected?.call(conn),
                          ),
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
                  child: _ConnectionTile(
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
