part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── Redis connection tile with expandable database tree ────────────────────

class _RedisConnectionTile extends StatefulWidget {
  const _RedisConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    required this.onEdit,
    this.onTap,
    this.onDatabaseTap,
    this.isExpanded = false,
    this.onExpandedChanged,
  });

  final ConnectionRow connection;
  final bool isSelected;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback? onTap;
  final void Function(int database)? onDatabaseTap;
  final bool isExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<_RedisConnectionTile> createState() => _RedisConnectionTileState();
}

class _RedisConnectionTileState extends State<_RedisConnectionTile> {
  bool get _expanded => widget.isExpanded;
  bool _loading = false;
  String? _error;
  // All 16 databases (db0–db15) with key counts
  List<({int index, int keys})> _databases = [];

  @override
  void initState() {
    super.initState();
    if (widget.isExpanded) {
      _loadDatabases();
    }
  }

  @override
  void didUpdateWidget(_RedisConnectionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded && !oldWidget.isExpanded) {
      if (_databases.isEmpty && !_loading) {
        _loadDatabases();
      }
    } else if (!widget.isExpanded && oldWidget.isExpanded) {
      setState(() {
        _databases = [];
        _loading = false;
        _error = null;
      });
    }
  }

  void _toggle() {
    widget.onExpandedChanged?.call(!widget.isExpanded);
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
            width: QueryaIconSizes.sidebarConnectionIcon,
            height: QueryaIconSizes.sidebarConnectionIcon,
            fit: material.BoxFit.contain,
            errorBuilder: (_, __, ___) => material.Icon(
              widget.icon,
              size: QueryaIconSizes.sidebarConnectionIcon,
              color: theme.colorScheme.primary,
            ),
          )
        : material.Icon(widget.icon,
            size: QueryaIconSizes.sidebarConnectionIcon,
            color: theme.colorScheme.primary);

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
          leading: material.Icon(material.Icons.edit_outlined,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) => widget.onEdit(),
          child: const Text('Edit connection…'),
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
                  child: material.Semantics(
                    button: true,
                    expanded: _expanded,
                    child: material.InkWell(
                      onTap: _toggle,
                      borderRadius: material.BorderRadius.circular(4),
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(2),
                        child: material.AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration:
                              context.motionDuration(QueryaMotion.treeExpand),
                          curve:
                              context.motionCurve(QueryaMotion.treeExpandCurve),
                          child: material.Icon(
                            QueryaIcons.expandClosed,
                            size: QueryaIconSizes.sidebarExpand,
                            color: theme.colorScheme.mutedForeground,
                          ),
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
            // Expanded database children — ALL 16 databases
            QueryaAnimatedExpand(
              expanded: _expanded,
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  if (_loading)
                    material.Padding(
                      padding: const material.EdgeInsets.only(
                          left: 28, top: 4, bottom: 4),
                      child: material.Row(
                        children: [
                          const material.SizedBox(
                            width: 12,
                            height: 12,
                            child: material.CircularProgressIndicator(
                                strokeWidth: 1.5),
                          ),
                          const Gap(8),
                          const Text('Loading...').muted().xSmall(),
                        ],
                      ),
                    ),
                  if (_error != null)
                    TreeLoadError(
                      title: 'Could not load Redis info',
                      message: _error!,
                      padding: const material.EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      onRetry: _loadDatabases,
                    ),
                  if (_databases.isNotEmpty)
                    _RedisDatabasesNode(
                      connection: widget.connection,
                      databases: _databases,
                      onRefreshDatabases: () {
                        setState(() => _databases = []);
                        _loadDatabases();
                      },
                      onDatabaseTap: widget.onDatabaseTap,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedisDatabasesNode extends material.StatelessWidget {
  const _RedisDatabasesNode({
    required this.connection,
    required this.databases,
    required this.onRefreshDatabases,
    this.onDatabaseTap,
  });

  final ConnectionRow connection;
  final List<({int index, int keys})> databases;
  final VoidCallback onRefreshDatabases;
  final void Function(int database)? onDatabaseTap;

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
            label: 'Databases (${databases.length})',
            icon: QueryaIcons.databasesFolder,
            iconSize: QueryaIconSizes.treeConnection,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            onTap: null,
            connection: connection,
            onContextRefresh: onRefreshDatabases,
          ),
          lazyConnectionTreeList(
            context: context,
            itemCount: databases.length,
            itemBuilder: (context, index) {
              final db = databases[index];
              return _RedisDatabaseNode(
                index: db.index,
                keys: db.keys,
                onTap: () => onDatabaseTap?.call(db.index),
              );
            },
          ),
        ],
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
      padding: const material.EdgeInsets.only(left: 16),
      child: _PgTreeRow(
        label: 'db$index',
        icon: QueryaIcons.database,
        iconSize: QueryaIconSizes.treeConnection,
        iconColor: keys > 0
            ? theme.colorScheme.primary.withValues(alpha: 0.7)
            : theme.colorScheme.mutedForeground.withValues(alpha: 0.5),
        trailing: keys > 0
            ? material.Text(
                '$keys',
                style: material.TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.mutedForeground,
                ),
              )
            : null,
        textStyle: material.TextStyle(
          fontSize: 12,
          color: keys > 0
              ? theme.colorScheme.foreground
              : theme.colorScheme.mutedForeground,
        ),
        verticalPadding: 3,
        onTap: onTap,
      ),
    );
  }
}
