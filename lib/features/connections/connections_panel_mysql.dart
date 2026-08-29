part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── MySQL connection tile (databases → tables) ───────────────────────────────

class _MysqlConnectionTile extends StatefulWidget {
  const _MysqlConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    required this.onEdit,
    this.onTap,
    this.onMysqlObjectSelected,
    this.onMysqlOpenSqlWorkspace,
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
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  )? onMysqlObjectSelected;
  final void Function(ConnectionRow connection)? onMysqlOpenSqlWorkspace;
  final bool isExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<_MysqlConnectionTile> createState() => _MysqlConnectionTileState();
}

class _MysqlConnectionTileState extends State<_MysqlConnectionTile> {
  bool get _expanded => widget.isExpanded;
  bool _loading = false;
  String? _error;
  List<String> _databases = [];

  @override
  void initState() {
    super.initState();
    if (widget.isExpanded) {
      _loadDatabases();
    }
  }

  @override
  void didUpdateWidget(_MysqlConnectionTile oldWidget) {
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
    MysqlLease? lease;
    try {
      final c = widget.connection;
      lease = await MysqlService.instance.acquire(
        c,
        database: c.databaseName ?? '',
        mode: MysqlSessionMode.readOnly,
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
            width: QueryaIconSizes.sidebarConnectionIcon,
            height: QueryaIconSizes.sidebarConnectionIcon,
            cacheWidth: (QueryaIconSizes.sidebarConnectionIcon * MediaQuery.devicePixelRatioOf(context)).toInt(),
            cacheHeight: (QueryaIconSizes.sidebarConnectionIcon * MediaQuery.devicePixelRatioOf(context)).toInt(),
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
        if (widget.onMysqlOpenSqlWorkspace != null)
          MenuButton(
            leading: material.Icon(material.Icons.terminal_rounded,
                size: 18, color: theme.colorScheme.mutedForeground),
            onPressed: (_) =>
                widget.onMysqlOpenSqlWorkspace!(widget.connection),
            child: const Text('Open in SQL'),
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
            material.Row(
              children: [
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
                      title: 'Could not load databases',
                      message: _error!,
                      padding: const material.EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      onRetry: _loadDatabases,
                    ),
                  if (_databases.isNotEmpty)
                    _MysqlDatabasesNode(
                      connection: widget.connection,
                      databases: _databases,
                      onRefreshDatabases: () {
                        setState(() => _databases = []);
                        _loadDatabases();
                      },
                      onMysqlObjectSelected: widget.onMysqlObjectSelected,
                      onMysqlOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
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

class _MysqlDatabasesNode extends material.StatelessWidget {
  const _MysqlDatabasesNode({
    required this.connection,
    required this.databases,
    required this.onRefreshDatabases,
    this.onMysqlObjectSelected,
    this.onMysqlOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final List<String> databases;
  final VoidCallback onRefreshDatabases;
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  )? onMysqlObjectSelected;
  final void Function(ConnectionRow connection)? onMysqlOpenSqlWorkspace;

  @override
  material.Widget build(material.BuildContext context) {
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
            onOpenSqlWorkspace: onMysqlOpenSqlWorkspace == null
                ? null
                : (c, {database, schema, name, kind}) =>
                    onMysqlOpenSqlWorkspace!(c),
          ),
          lazyConnectionTreeList(
            context: context,
            itemCount: databases.length,
            itemBuilder: (context, index) {
              final db = databases[index];
              return _MysqlDatabaseNode(
                key: material.ValueKey('mysql-db-${connection.id ?? 0}-$db'),
                connection: connection,
                databaseName: db,
                onMysqlObjectSelected: onMysqlObjectSelected,
                onMysqlOpenSqlWorkspace: onMysqlOpenSqlWorkspace,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MysqlDatabaseNode extends StatefulWidget {
  const _MysqlDatabaseNode({
    super.key,
    required this.connection,
    required this.databaseName,
    this.onMysqlObjectSelected,
    this.onMysqlOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final String databaseName;
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  )? onMysqlObjectSelected;
  final void Function(ConnectionRow connection)? onMysqlOpenSqlWorkspace;

  @override
  State<_MysqlDatabaseNode> createState() => _MysqlDatabaseNodeState();
}

class _MysqlDatabaseNodeState extends State<_MysqlDatabaseNode> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _tables = [];
  List<String> _views = [];
  List<String> _procedures = [];
  List<String> _functions = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded &&
        _tables.isEmpty &&
        _views.isEmpty &&
        _procedures.isEmpty &&
        _functions.isEmpty &&
        !_loading) {
      _loadTables();
    }
  }

  Future<void> _loadTables() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    MysqlLease? lease;
    try {
      final c = widget.connection;
      lease = await MysqlService.instance.acquire(
        c,
        database: widget.databaseName,
        mode: MysqlSessionMode.readOnly,
      );
      final tables =
          await lease.connection.listTables(schema: widget.databaseName);
      final views =
          await lease.connection.listViews(schema: widget.databaseName);
      final procs =
          await lease.connection.listProcedures(schema: widget.databaseName);
      final funcs =
          await lease.connection.listFunctions(schema: widget.databaseName);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _views = views;
        _procedures = procs;
        _functions = funcs;
        _loading = false;
        _error = null;
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
              duration: context.motionDuration(QueryaMotion.treeExpand),
              curve: context.motionCurve(QueryaMotion.treeExpandCurve),
              child: material.Icon(
                QueryaIcons.expandClosed,
                size: QueryaIconSizes.treeExpand,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: QueryaIcons.database,
            iconSize: QueryaIconSizes.treeConnection,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            expanded: _expanded,
            onTap: _toggle,
            connection: widget.connection,
            onContextRefresh: _loadTables,
            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace == null
                ? null
                : (c, {database, schema, name, kind}) =>
                    widget.onMysqlOpenSqlWorkspace!(c),
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  material.Padding(
                    padding: const material.EdgeInsets.only(
                        left: 24, top: 2, bottom: 2),
                    child: material.Row(
                      children: [
                        const material.SizedBox(
                          width: 10,
                          height: 10,
                          child: material.CircularProgressIndicator(
                              strokeWidth: 1.5),
                        ),
                        const Gap(6),
                        const Text('Loading...').muted().xSmall(),
                      ],
                    ),
                  )
                else if (_error != null)
                  TreeLoadError(
                    title: 'Could not load tables',
                    message: _error!,
                    onRetry: _loadTables,
                  ),
                if (_tables.isNotEmpty ||
                    _views.isNotEmpty ||
                    _procedures.isNotEmpty ||
                    _functions.isNotEmpty)
                  material.Padding(
                    padding: const material.EdgeInsets.only(left: 16),
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        if (_tables.isNotEmpty)
                          _MysqlObjectGroup(
                            connection: widget.connection,
                            databaseName: widget.databaseName,
                            objectKind: MysqlObjectKind.table,
                            onRefresh: _loadTables,
                            label: 'Tables',
                            icon: QueryaIcons.tableGroup,
                            itemIcon: QueryaIcons.tableLeaf,
                            items: _tables,
                            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
                            onItemTap: widget.onMysqlObjectSelected == null
                                ? null
                                : (name) => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      name,
                                      MysqlObjectKind.table,
                                    ),
                          ),
                        if (_views.isNotEmpty)
                          _MysqlObjectGroup(
                            connection: widget.connection,
                            databaseName: widget.databaseName,
                            objectKind: MysqlObjectKind.view,
                            onRefresh: _loadTables,
                            label: 'Views',
                            icon: QueryaIcons.viewGroup,
                            itemIcon: QueryaIcons.viewLeaf,
                            items: _views,
                            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
                            onItemTap: widget.onMysqlObjectSelected == null
                                ? null
                                : (name) => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      name,
                                      MysqlObjectKind.view,
                                    ),
                          ),
                        if (_procedures.isNotEmpty)
                          _MysqlObjectGroup(
                            connection: widget.connection,
                            databaseName: widget.databaseName,
                            objectKind: MysqlObjectKind.procedure,
                            onRefresh: _loadTables,
                            label: 'Procedures',
                            icon: QueryaIcons.functionGroup,
                            itemIcon: QueryaIcons.functionLeaf,
                            items: _procedures,
                            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
                            onItemTap: widget.onMysqlObjectSelected == null
                                ? null
                                : (name) => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      name,
                                      MysqlObjectKind.procedure,
                                    ),
                          ),
                        if (_functions.isNotEmpty)
                          _MysqlObjectGroup(
                            connection: widget.connection,
                            databaseName: widget.databaseName,
                            objectKind: MysqlObjectKind.function,
                            onRefresh: _loadTables,
                            label: 'Functions',
                            icon: QueryaIcons.functionGroup,
                            itemIcon: QueryaIcons.functionLeaf,
                            items: _functions,
                            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
                            onItemTap: widget.onMysqlObjectSelected == null
                                ? null
                                : (name) => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      name,
                                      MysqlObjectKind.function,
                                    ),
                          ),
                      ],
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

class _MysqlObjectGroup extends StatefulWidget {
  const _MysqlObjectGroup({
    required this.connection,
    required this.databaseName,
    required this.objectKind,
    required this.onRefresh,
    required this.label,
    required this.icon,
    required this.itemIcon,
    required this.items,
    this.onItemTap,
    this.onOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final String databaseName;
  final MysqlObjectKind objectKind;
  final VoidCallback onRefresh;
  final String label;
  final material.IconData icon;
  final material.IconData itemIcon;
  final List<String> items;
  final void Function(String itemName)? onItemTap;
  final void Function(ConnectionRow connection)? onOpenSqlWorkspace;

  @override
  State<_MysqlObjectGroup> createState() => _MysqlObjectGroupState();
}

class _MysqlObjectGroupState extends State<_MysqlObjectGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.only(bottom: 2),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          _PgTreeRow(
            label: '${widget.label} (${widget.items.length})',
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: context.motionDuration(QueryaMotion.treeExpand),
              curve: context.motionCurve(QueryaMotion.treeExpandCurve),
              child: material.Icon(
                QueryaIcons.expandClosed,
                size: QueryaIconSizes.treeExpand,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: widget.icon,
            iconSize: QueryaIconSizes.treeGroup,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefresh,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: lazyConnectionTreeList(
              context: context,
              itemCount: widget.items.length,
              itemExtent: kConnectionTreeRowExtent,
              padding: const material.EdgeInsets.only(left: 26),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final sel = _ConnectionsTreeSelectionScope.of(context);
                final isSelected = sel != null &&
                    sel.selectedConnectionId == widget.connection.id &&
                    sel.selectedMysqlObject != null &&
                    sel.selectedMysqlObject!.database == widget.databaseName &&
                    sel.selectedMysqlObject!.name == item &&
                    sel.selectedMysqlObject!.kind == widget.objectKind;
                return _PgTreeRow(
                  key: material.ValueKey(
                    'mysql-${widget.objectKind.name}-${widget.databaseName}-$item',
                  ),
                  label: item,
                  isSelected: isSelected,
                  icon: widget.itemIcon,
                  iconSize: QueryaIconSizes.treeLeaf,
                  iconColor: QueryaTreeTokens.leafIconColor(
                    theme.colorScheme.primary,
                  ),
                  textStyle: material.TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.foreground,
                  ),
                  verticalPadding: 2,
                  onTap: widget.onItemTap != null
                      ? () => widget.onItemTap!(item)
                      : null,
                  connection: widget.connection,
                  openSqlDatabase: widget.databaseName,
                  openSqlName: item,
                  onContextRefresh: widget.onRefresh,
                  onOpenSqlWorkspace: widget.onOpenSqlWorkspace != null
                      ? (conn, {database, schema, name, kind}) =>
                          widget.onOpenSqlWorkspace!(conn)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
