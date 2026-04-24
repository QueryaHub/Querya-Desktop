part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── MongoDB connection tile with expandable database tree ──────────────────

class _MongoConnectionTile extends StatefulWidget {
  const _MongoConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onDatabaseTap,
  });

  final ConnectionRow connection;
  final bool isSelected;
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
                        duration: const Duration(milliseconds: 100),
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
                  child: _sidebarConnectionShell(
                    context: context,
                    isSelected: widget.isSelected,
                    onTap: widget.onTap,
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
