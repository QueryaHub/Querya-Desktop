part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── MySQL connection tile (databases → tables) ───────────────────────────────

class _MysqlConnectionTile extends StatefulWidget {
  const _MysqlConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onMysqlObjectSelected,
    this.onMysqlOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final bool isSelected;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  )? onMysqlObjectSelected;
  final void Function(ConnectionRow connection)? onMysqlOpenSqlWorkspace;

  @override
  State<_MysqlConnectionTile> createState() => _MysqlConnectionTileState();
}

class _MysqlConnectionTileState extends State<_MysqlConnectionTile> {
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
        if (widget.onMysqlOpenSqlWorkspace != null)
          MenuButton(
            leading: material.Icon(material.Icons.terminal_rounded,
                size: 18, color: theme.colorScheme.mutedForeground),
            onPressed: (_) => widget.onMysqlOpenSqlWorkspace!(widget.connection),
            child: const Text('Open in SQL'),
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
                                      color:
                                          theme.colorScheme.mutedForeground,
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
            icon: material.Icons.dns_rounded,
            iconSize: 14,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            onTap: null,
            connection: connection,
            onContextRefresh: onRefreshDatabases,
            onOpenSqlWorkspace: onMysqlOpenSqlWorkspace,
          ),
          for (final db in databases)
            _MysqlDatabaseNode(
              key: material.ValueKey('mysql-db-${connection.id ?? 0}-$db'),
              connection: connection,
              databaseName: db,
              onMysqlObjectSelected: onMysqlObjectSelected,
              onMysqlOpenSqlWorkspace: onMysqlOpenSqlWorkspace,
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
  List<String> _tables = [];
  List<String> _views = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _tables.isEmpty && _views.isEmpty && !_loading) {
      _loadTables();
    }
  }

  Future<void> _loadTables() async {
    if (!mounted) return;
    setState(() => _loading = true);
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
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _views = views;
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
              duration: const Duration(milliseconds: 100),
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
            onContextRefresh: _loadTables,
            onOpenSqlWorkspace: widget.onMysqlOpenSqlWorkspace,
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
            if (_tables.isNotEmpty || _views.isNotEmpty)
              material.Padding(
                padding: const material.EdgeInsets.only(left: 16),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    if (_tables.isNotEmpty) ...[
                      _PgTreeRow(
                        label: 'Tables (${_tables.length})',
                        icon: material.Icons.table_chart_rounded,
                        iconSize: 13,
                        iconColor: theme.colorScheme.mutedForeground,
                        textStyle: material.TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        verticalPadding: 3,
                        onTap: null,
                        connection: widget.connection,
                        onContextRefresh: _loadTables,
                        onOpenSqlWorkspace: null,
                      ),
                      for (final t in _tables)
                        material.Padding(
                          padding: const material.EdgeInsets.only(left: 12),
                          child: _PgTreeRow(
                            label: t,
                            icon: material.Icons.grid_on_rounded,
                            iconSize: 12,
                            iconColor: theme.colorScheme.mutedForeground,
                            textStyle: material.TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.foreground,
                            ),
                            verticalPadding: 2,
                            onTap: widget.onMysqlObjectSelected == null
                                ? null
                                : () => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      t,
                                      MysqlObjectKind.table,
                                    ),
                            connection: widget.connection,
                            onContextRefresh: null,
                            onOpenSqlWorkspace: null,
                          ),
                        ),
                    ],
                    if (_views.isNotEmpty) ...[
                      _PgTreeRow(
                        label: 'Views (${_views.length})',
                        icon: material.Icons.view_agenda_rounded,
                        iconSize: 13,
                        iconColor: theme.colorScheme.mutedForeground,
                        textStyle: material.TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        verticalPadding: 3,
                        onTap: null,
                        connection: widget.connection,
                        onContextRefresh: _loadTables,
                        onOpenSqlWorkspace: null,
                      ),
                      for (final v in _views)
                        material.Padding(
                          padding: const material.EdgeInsets.only(left: 12),
                          child: _PgTreeRow(
                            label: v,
                            icon: material.Icons.view_week_rounded,
                            iconSize: 12,
                            iconColor: theme.colorScheme.mutedForeground,
                            textStyle: material.TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.foreground,
                            ),
                            verticalPadding: 2,
                            onTap: widget.onMysqlObjectSelected == null
                                ? null
                                : () => widget.onMysqlObjectSelected!(
                                      widget.connection,
                                      widget.databaseName,
                                      v,
                                      MysqlObjectKind.view,
                                    ),
                            connection: widget.connection,
                            onContextRefresh: null,
                            onOpenSqlWorkspace: null,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
