import 'package:flutter/material.dart' as material show Padding, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, AnimatedContainer, Curves, SystemMouseCursors, DefaultTextStyle, TextStyle, CustomScrollView, SliverToBoxAdapter, SliverFillRemaining, SliverPadding, GestureDetector, HitTestBehavior, SizedBox, Column;
import 'package:querya_desktop/core/storage/folders_storage.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'mongodb_connection_form.dart';
import 'new_connection_dialog.dart';
import 'new_folder_dialog.dart';

/// Left panel: Browser tree (pgAdmin-style). Uses shadcn layout widgets.
class ConnectionsPanel extends StatefulWidget {
  const ConnectionsPanel({super.key});

  @override
  State<ConnectionsPanel> createState() => _ConnectionsPanelState();
}

class _ConnectionsPanelState extends State<ConnectionsPanel> {
  List<String> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final list = await FoldersStorage.instance.load();
    if (mounted) setState(() => _folders = list);
  }

  Future<void> _createFolder(BuildContext menuContext) async {
    final name = await showNewFolderDialog(menuContext);
    if (name == null || !mounted) return;
    await FoldersStorage.instance.add(name);
    if (mounted) setState(() => _folders = FoldersStorage.instance.folders);
  }

  Future<void> _createConnectionInFolder(String folderName) async {
    final type = await showNewConnectionDialog(context);
    if (type == null || !mounted) return;
    
    final folderId = await LocalDb.instance.getFolderIdByName(folderName);
    ConnectionRow? row;
    
    if (type == ConnectionType.mongodb) {
      row = await showMongoConnectionForm(context, folderId: folderId);
    } else {
      // For other types, create default connection
      row = ConnectionRow(
        type: type.name,
        name: '${type.label} connection',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        folderId: folderId,
      );
    }
    
    if (row != null && mounted) {
      await LocalDb.instance.addConnection(row);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              child: Text('Browser').semiBold().small(),
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
                        for (final name in _folders)
                          _FolderTile(
                            name: name,
                            onRemove: () async {
                              await FoldersStorage.instance.remove(name);
                              if (mounted) setState(() => _folders = FoldersStorage.instance.folders);
                            },
                            onNewConnection: (folderName) => _createConnectionInFolder(folderName),
                          ),
                        material.Padding(
                          padding: const material.EdgeInsets.only(top: 8),
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
                              
                              // Wait a bit for the dialog to fully close
                              await Future.delayed(const Duration(milliseconds: 100));
                              if (!mounted) return;
                              
                              ConnectionRow? row;
                              if (type == ConnectionType.mongodb) {
                                // Use the widget's context instead of menuContext for navigation
                                row = await showMongoConnectionForm(context);
                              } else {
                                // For other types, create default connection
                                row = ConnectionRow(
                                  type: type.name,
                                  name: '${type.label} connection',
                                  createdAt: DateTime.now().toUtc().toIso8601String(),
                                );
                              }
                              
                              if (row != null && mounted) {
                                await LocalDb.instance.addConnection(row);
                                if (mounted) setState(() {});
                              }
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
      child: Row(
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

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.name,
    required this.onRemove,
    required this.onNewConnection,
  });

  final String name;
  final VoidCallback onRemove;
  final void Function(String folderName) onNewConnection;

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
        child: material.MouseRegion(
          cursor: material.SystemMouseCursors.click,
          child: material.InkWell(
            onTap: () {},
            borderRadius: material.BorderRadius.circular(6),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  material.Icon(material.Icons.folder_rounded, size: 18, color: theme.colorScheme.primary),
                  const Gap(8),
                  Expanded(child: Text(name).small()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
