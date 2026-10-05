part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── MongoDB connection tile with expandable database tree ──────────────────

class _MongoConnectionTile extends StatefulWidget {
  const _MongoConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    required this.onEdit,
    this.onTap,
    this.onDatabaseTap,
    this.onCollectionTap,
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
  final void Function(String database)? onDatabaseTap;
  final void Function(String database, String collection)? onCollectionTap;
  final bool isExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<_MongoConnectionTile> createState() => _MongoConnectionTileState();
}

class _MongoConnectionTileState extends State<_MongoConnectionTile> {
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
  void didUpdateWidget(_MongoConnectionTile oldWidget) {
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
      final conn =
          await MongoService.instance.ensureConnected(widget.connection);
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
    final ok = await QueryaConfirmDialog.show(
      context: context,
      title: 'Drop database?',
      message:
          'Permanently delete database "$dbName"? This cannot be undone.',
      confirmLabel: 'Drop database',
      isDestructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      final conn =
          await MongoService.instance.ensureConnected(widget.connection);
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
            // Expanded database children
            QueryaAnimatedExpand(
              expanded: _expanded,
              estimatedChildCount: _databases.length,
              child: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  if (_loading)
                    const ConnectionTreeLoadingRow.connection(),
                  if (_error != null)
                    TreeLoadError(
                      title: 'Could not load databases',
                      message: _error!,
                      padding: QueryaTreeTokens.errorPaddingConnection,
                      onRetry: _loadDatabases,
                    ),
                  if (_databases.isNotEmpty)
                    _MongoDatabasesNode(
                      connection: widget.connection,
                      databases: _databases,
                      onDatabaseTap: widget.onDatabaseTap,
                      onCollectionTap: widget.onCollectionTap,
                      onDeleteDatabase: _deleteDatabase,
                      onRefreshDatabases: () {
                        setState(() => _databases = []);
                        _loadDatabases();
                      },
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

class _MongoDatabasesNode extends StatelessWidget {
  const _MongoDatabasesNode({
    required this.connection,
    required this.databases,
    required this.onRefreshDatabases,
    required this.onDeleteDatabase,
    this.onDatabaseTap,
    this.onCollectionTap,
  });

  final ConnectionRow connection;
  final List<String> databases;
  final VoidCallback onRefreshDatabases;
  final Future<void> Function(String name) onDeleteDatabase;
  final void Function(String database)? onDatabaseTap;
  final void Function(String database, String collection)? onCollectionTap;

  @override
  Widget build(BuildContext context) {
    return ConnectionDatabasesFolder(
      connection: connection,
      databaseCount: databases.length,
      onRefresh: onRefreshDatabases,
      child: lazyConnectionTreeList(
        context: context,
        itemCount: databases.length,
        itemBuilder: (context, index) {
          final db = databases[index];
          return _MongoDatabaseNode(
            key: material.ValueKey('mongo-db-${connection.id ?? 0}-$db'),
            connection: connection,
            name: db,
            onTap: () => onDatabaseTap?.call(db),
            onCollectionTap: onCollectionTap,
            onDelete: () => onDeleteDatabase(db),
            onRefreshDatabases: onRefreshDatabases,
          );
        },
      ),
    );
  }
}

class _MongoDatabaseNode extends StatefulWidget {
  const _MongoDatabaseNode({
    super.key,
    required this.connection,
    required this.name,
    required this.onTap,
    required this.onDelete,
    required this.onRefreshDatabases,
    this.onCollectionTap,
  });

  final ConnectionRow connection;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRefreshDatabases;
  final void Function(String database, String collection)? onCollectionTap;

  @override
  State<_MongoDatabaseNode> createState() => _MongoDatabaseNodeState();
}

class _MongoDatabaseNodeState extends State<_MongoDatabaseNode> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _collections = [];
  final _filterController = material.TextEditingController();
  final _filterDebouncer = FilterDebouncer();
  String _filter = '';

  @override
  void dispose() {
    _filterDebouncer.cancel();
    _filterController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _collections.isEmpty && !_loading) {
      _loadCollections();
    }
  }

  Future<void> _loadCollections() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conn =
          await MongoService.instance.ensureConnected(widget.connection);
      final colls = await conn.listCollections(widget.name);
      colls.sort();
      if (!mounted) return;
      setState(() {
        _collections = colls;
        _loading = false;
        _error = null;
      });
      final cacheId = widget.connection.id;
      if (cacheId != null) {
        QueryaSchemaObjectCache.instance.merge(
          cacheId,
          QueryaSchemaObjectCache.scopeMongo(widget.name),
          [
            for (final name in colls)
              QueryaSchemaObject.mongo(
                database: widget.name,
                name: name,
              ),
          ],
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _dropCollection(String collName) async {
    if (!mounted) return;
    final ok = await QueryaConfirmDialog.show(
      context: context,
      title: 'Drop collection?',
      message:
          'Permanently delete collection "$collName" from database "${widget.name}"? This cannot be undone.',
      confirmLabel: 'Drop collection',
      isDestructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      final conn =
          await MongoService.instance.ensureConnected(widget.connection);
      await MongoService.instance.dropCollection(conn, widget.name, collName);
      if (mounted) {
        await _loadCollections();
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
    final query = _filter.trim().toLowerCase();
    final matching = query.isEmpty
        ? _collections
        : _collections.where((it) => it.toLowerCase().contains(query)).toList();

    final showFilter = _collections.length >= 8 || _filter.isNotEmpty;

    return QueryaTreeIndentGuide(
      depth: 1,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          _ConnectionsTreeSelectionBuilder<bool>(
            select: (sel) =>
                sel.selectedConnectionId == widget.connection.id &&
                sel.selectedMongoDb == widget.name &&
                sel.selectedMongoCollection == null,
            builder: (context, isSelected) {
              return QueryaConnectionTreeRow(
                label: widget.name,
                isSelected: isSelected,
                leading: material.MouseRegion(
                  cursor: material.SystemMouseCursors.click,
                  child: material.InkWell(
                    onTap: _toggle,
                    borderRadius: material.BorderRadius.circular(4),
                    child: material.AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: context.motionDuration(QueryaMotion.treeExpand),
                      curve: context.motionCurve(QueryaMotion.treeExpandCurve),
                      child: material.Icon(
                        QueryaIcons.expandClosed,
                        size: QueryaIconSizes.treeExpand,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                ),
                icon: QueryaIcons.database,
                iconSize: QueryaIconSizes.treeConnection,
                iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
                textStyle: material.TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.foreground,
                ),
                verticalPadding: 3,
                expanded: _expanded,
                onTap: () {
                  widget.onTap();
                  if (!_expanded) {
                    _toggle();
                  }
                },
                connection: widget.connection,
                onContextRefresh: () {
                  widget.onRefreshDatabases();
                  if (_expanded) {
                    _loadCollections();
                  }
                },
                onOpenSqlWorkspace: null,
                onContextDelete: widget.onDelete,
                contextDeleteLabel: 'Delete database',
              );
            },
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            estimatedChildCount: _collections.length,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const ConnectionTreeLoadingRow.nested()
                else if (_error != null)
                  TreeLoadError(
                    title: 'Could not load collections',
                    message: _error!,
                    onRetry: _loadCollections,
                  )
                else ...[
                  if (showFilter)
                    TreeObjectFilterBar(
                      controller: _filterController,
                      hintText: 'Filter collections...',
                      onChanged: (val) => _filterDebouncer.run(() {
                        if (mounted) setState(() => _filter = val);
                      }),
                      onClear: () {
                        _filterDebouncer.cancel();
                        setState(() {
                          _filter = '';
                          _filterController.clear();
                        });
                      },
                      filteredCount: matching.length,
                      totalCount: _collections.length,
                    ),
                  if (matching.isEmpty && _collections.isNotEmpty)
                    material.Padding(
                      padding: QueryaTreeTokens.emptyFilterPadding,
                      child: const Text('No matching collections')
                          .muted()
                          .xSmall(),
                    )
                  else if (_collections.isEmpty && !_loading)
                    material.Padding(
                      padding: const material.EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      child: const Text('No collections')
                          .muted()
                          .xSmall(),
                    )
                  else
                    QueryaTreeIndentGuide(
                      depth: 1,
                      child: lazyConnectionTreeList(
                        context: context,
                        itemCount: matching.length,
                        itemExtent: kConnectionTreeRowExtent,
                        itemBuilder: (context, index) {
                          final collName = matching[index];
                          return _MongoCollectionNode(
                            key: material.ValueKey(
                              'mongo-col-${widget.connection.id}-${widget.name}-$collName',
                            ),
                            connection: widget.connection,
                            database: widget.name,
                            name: collName,
                            onTap: () {
                              widget.onCollectionTap?.call(widget.name, collName);
                            },
                            onRefreshCollections: _loadCollections,
                            onDropCollection: _dropCollection,
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MongoCollectionNode extends StatelessWidget {
  const _MongoCollectionNode({
    super.key,
    required this.connection,
    required this.database,
    required this.name,
    required this.onTap,
    required this.onRefreshCollections,
    required this.onDropCollection,
  });

  final ConnectionRow connection;
  final String database;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onRefreshCollections;
  final Future<void> Function(String name) onDropCollection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ConnectionsTreeSelectionBuilder<bool>(
      select: (sel) =>
          sel.selectedConnectionId == connection.id &&
          sel.selectedMongoDb == database &&
          sel.selectedMongoCollection == name,
      builder: (context, isSelected) {
        return ContextMenu(
          items: [
            MenuButton(
              leading: material.Icon(
                material.Icons.description_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              onPressed: (_) => onTap(),
              child: const Text('Open collection'),
            ),
            MenuButton(
              leading: material.Icon(
                material.Icons.copy_rounded,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
              onPressed: (_) {
                Clipboard.setData(ClipboardData(text: name));
              },
              child: const Text('Copy name'),
            ),
            const MenuDivider(),
            MenuButton(
              leading: material.Icon(
                material.Icons.refresh_rounded,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
              onPressed: (_) => onRefreshCollections(),
              child: const Text('Refresh'),
            ),
            MenuButton(
              leading: material.Icon(
                material.Icons.delete_outline_rounded,
                size: 18,
                color: theme.colorScheme.destructive,
              ),
              onPressed: (_) => onDropCollection(name),
              child: const Text('Drop collection'),
            ),
          ],
          child: QueryaConnectionTreeRow(
            label: name,
            isSelected: isSelected,
            icon: material.Icons.table_chart_outlined,
            iconSize: QueryaIconSizes.treeLeaf,
            iconColor: QueryaTreeTokens.leafIconColor(theme.colorScheme.primary),
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 2,
            onTap: onTap,
            connection: null,
          ),
        );
      },
    );
  }
}
