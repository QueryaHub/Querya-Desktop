part of 'package:querya_desktop/features/connections/connections_panel.dart';

material.Widget _sidebarConnectionShell({
  required material.BuildContext context,
  required bool isSelected,
  required material.VoidCallback? onTap,
  required material.Widget child,
}) {
  final p = Theme.of(context).colorScheme.primary;
  return material.Material(
    color: material.Colors.transparent,
    child: material.InkWell(
      onTap: onTap,
      borderRadius: material.BorderRadius.circular(20),
      mouseCursor: onTap != null
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      child: material.Container(
        decoration: material.BoxDecoration(
          color: isSelected ? p.withValues(alpha: 0.16) : null,
          borderRadius: material.BorderRadius.circular(20),
          border: isSelected
              ? material.Border.all(color: p.withValues(alpha: 0.26))
              : null,
        ),
        child: child,
      ),
    ),
  );
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
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
  });

  final ConnectionRow connection;
  final bool isSelected;
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
        child: _sidebarConnectionShell(
          context: context,
          isSelected: isSelected,
          onTap: onTap,
          child: material.Padding(
            padding:
                const material.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    );
  }
}

class _FolderTile extends StatefulWidget {
  const _FolderTile({
    required this.name,
    required this.initiallyExpanded,
    required this.onExpansionCommitted,
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
  final bool initiallyExpanded;
  final void Function(String folderName, bool expanded) onExpansionCommitted;
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
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(_FolderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name ||
        widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionCommitted(widget.name, _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.settings_ethernet_rounded, size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (menuContext) => widget.onNewConnection(widget.name),
          child: const Text('New connection'),
        ),
        MenuButton(
          leading: material.Icon(material.Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => widget.onRemove(),
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
                onTap: _toggle,
                borderRadius: material.BorderRadius.circular(6),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: material.Row(
                    children: [
                      material.AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 100),
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
                          widget.name,
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
            if (_expanded)
              for (final conn in widget.connections)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 24),
                  child: widget.buildConnectionTile != null
                      ? widget.buildConnectionTile!(conn)
                      : _ConnectionTile(
                          connection: conn,
                          icon: widget.iconForType(conn.type),
                          iconAsset: ConnectionsPanelState._iconAssetForType(conn.type),
                          onRemove: () => widget.onRemoveConnection(conn.id!),
                          onTap: () => widget.onConnectionTap?.call(conn),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}
