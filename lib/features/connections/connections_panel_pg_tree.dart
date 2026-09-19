part of 'package:querya_desktop/features/connections/connections_panel.dart';

class _PgDatabasesNode extends StatelessWidget {
  const _PgDatabasesNode({
    required this.connection,
    required this.databases,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
    required this.onRefreshDatabases,
  });

  final ConnectionRow connection;
  final List<String> databases;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;
  final VoidCallback onRefreshDatabases;

  @override
  Widget build(BuildContext context) {
    return ConnectionDatabasesFolder(
      connection: connection,
      databaseCount: databases.length,
      onRefresh: onRefreshDatabases,
      onOpenSql: onPostgresOpenSqlWorkspace == null
          ? null
          : () => onPostgresOpenSqlWorkspace!(connection),
      child: lazyConnectionTreeList(
        context: context,
        itemCount: databases.length,
        itemBuilder: (context, index) {
          final db = databases[index];
          return _PgDatabaseNode(
            key: material.ValueKey('pg-db-${connection.id ?? 0}-$db'),
            connection: connection,
            databaseName: db,
            onPostgresObjectSelected: onPostgresObjectSelected,
            onPostgresOpenSqlWorkspace: onPostgresOpenSqlWorkspace,
          );
        },
      ),
    );
  }
}

class _PgDatabaseNode extends StatefulWidget {
  const _PgDatabaseNode({
    super.key,
    required this.connection,
    required this.databaseName,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final String databaseName;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;

  @override
  State<_PgDatabaseNode> createState() => _PgDatabaseNodeState();
}

class _PgDatabaseNodeState extends State<_PgDatabaseNode> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _schemas = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _schemas.isEmpty && !_loading) {
      _loadSchemas();
    }
  }

  Future<void> _loadSchemas() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: widget.databaseName,
        mode: PgSessionMode.readOnly,
      );
      final schemas = await lease.connection.listSchemas();
      if (!mounted) return;
      setState(() {
        _schemas = schemas;
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
    return QueryaTreeIndentGuide(
      depth: 1,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          QueryaConnectionTreeRow(
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
            onContextRefresh: _loadSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                _PgDbToolRow(
                  connection: widget.connection,
                  databaseName: widget.databaseName,
                  label: 'Extensions',
                  icon: QueryaIcons.extension,
                  kind: PostgresObjectKind.databaseExtensions,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                  onContextRefresh: _loadSchemas,
                ),
                _PgDbToolRow(
                  connection: widget.connection,
                  databaseName: widget.databaseName,
                  label: 'Foreign data',
                  icon: QueryaIcons.foreignData,
                  kind: PostgresObjectKind.databaseForeignData,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                  onContextRefresh: _loadSchemas,
                ),
                if (_loading)
                  const ConnectionTreeLoadingRow.nested()
                else if (_error != null)
                  TreeLoadError(
                    title: 'Could not load schemas',
                    message: _error!,
                    onRetry: _loadSchemas,
                  ),
                if (_schemas.isNotEmpty)
                  _PgSchemasNode(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemas: _schemas,
                    onPostgresObjectSelected: widget.onPostgresObjectSelected,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefreshSchemas: _loadSchemas,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PgDbToolRow extends material.StatelessWidget {
  const _PgDbToolRow({
    required this.connection,
    required this.databaseName,
    required this.label,
    required this.icon,
    required this.kind,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
    this.onContextRefresh,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String label;
  final material.IconData icon;
  final PostgresObjectKind kind;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;
  final VoidCallback? onContextRefresh;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.mutedForeground;
    return QueryaTreeIndentGuide(
      depth: 1,
      padding: const material.EdgeInsets.only(top: 2, bottom: 2),
      child: QueryaConnectionTreeRow(
        label: label,
        icon: icon,
        iconSize: QueryaIconSizes.treeGroup,
        iconColor: muted,
        trailing: material.Icon(
          QueryaIcons.expandClosed,
          size: QueryaIconSizes.treeExpand,
          color: muted,
        ),
        onTap: onPostgresObjectSelected == null
            ? null
            : () => onPostgresObjectSelected!(
                  connection,
                  databaseName,
                  '',
                  '',
                  kind,
                ),
        textStyle: material.TextStyle(
          fontSize: 11,
          color: muted,
        ),
        connection: connection,
        onContextRefresh: onContextRefresh,
        onOpenSqlWorkspace: onPostgresOpenSqlWorkspace,
      ),
    );
  }
}

class _PgSchemasNode extends StatefulWidget {
  const _PgSchemasNode({
    required this.connection,
    required this.databaseName,
    required this.schemas,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
    required this.onRefreshSchemas,
  });

  final ConnectionRow connection;
  final String databaseName;
  final List<String> schemas;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;
  final VoidCallback onRefreshSchemas;

  @override
  State<_PgSchemasNode> createState() => _PgSchemasNodeState();
}

class _PgSchemasNodeState extends State<_PgSchemasNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return QueryaTreeIndentGuide(
      depth: 1,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          QueryaConnectionTreeRow(
            label: 'Schemas (${widget.schemas.length})',
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
            icon: QueryaIcons.schemasFolder,
            iconSize: QueryaIconSizes.treeGroup,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            estimatedChildCount: widget.schemas.length,
            child: lazyConnectionTreeList(
              context: context,
              itemCount: widget.schemas.length,
              itemBuilder: (context, index) {
                final schema = widget.schemas[index];
                return _PgSchemaNode(
                  key: material.ValueKey(
                    'pg-schema-${widget.connection.id ?? 0}-${widget.databaseName}-$schema',
                  ),
                  connection: widget.connection,
                  databaseName: widget.databaseName,
                  schemaName: schema,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PgSchemaNode extends StatefulWidget {
  const _PgSchemaNode({
    super.key,
    required this.connection,
    required this.databaseName,
    required this.schemaName,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String schemaName;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;

  @override
  State<_PgSchemaNode> createState() => _PgSchemaNodeState();
}

class _PgSchemaNodeState extends State<_PgSchemaNode> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<String> _tables = [];
  List<String> _views = [];
  List<String> _matviews = [];
  List<String> _functions = [];
  List<String> _sequences = [];
  bool _loaded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && !_loaded && !_loading) {
      _loadObjects();
    }
  }

  Future<void> _loadObjects() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: widget.databaseName,
        mode: PgSessionMode.readOnly,
      );
      final conn = lease.connection;
      final tables = await conn.listTables(schema: widget.schemaName);
      final views = await conn.listViews(schema: widget.schemaName);
      List<String> matviews = [];
      try {
        matviews = await conn.listMaterializedViews(schema: widget.schemaName);
      } catch (_) {
        // pg_matviews / permissions may fail on some servers; keep tree usable.
      }
      final functions = await conn.listFunctions(schema: widget.schemaName);
      final sequences = await conn.listSequences(schema: widget.schemaName);
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _views = views;
        _matviews = matviews;
        _functions = functions;
        _sequences = sequences;
        _loading = false;
        _loaded = true;
        _error = null;
      });
      final cacheId = widget.connection.id;
      if (cacheId != null) {
        QueryaSchemaObjectCache.instance.merge(
          cacheId,
          QueryaSchemaObjectCache.scopePostgres(widget.databaseName),
          [
            for (final name in tables)
              QueryaSchemaObject.postgres(
                database: widget.databaseName,
                schema: widget.schemaName,
                name: name,
                kind: QueryaSchemaObjectKind.table,
              ),
            for (final name in views)
              QueryaSchemaObject.postgres(
                database: widget.databaseName,
                schema: widget.schemaName,
                name: name,
                kind: QueryaSchemaObjectKind.view,
              ),
            for (final name in matviews)
              QueryaSchemaObject.postgres(
                database: widget.databaseName,
                schema: widget.schemaName,
                name: name,
                kind: QueryaSchemaObjectKind.materializedView,
              ),
          ],
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loaded = false;
        _tables = [];
        _views = [];
        _matviews = [];
        _functions = [];
        _sequences = [];
      });
    } finally {
      lease?.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return QueryaTreeIndentGuide(
      depth: 1,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          QueryaConnectionTreeRow(
            label: widget.schemaName,
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
            icon: QueryaIcons.schema,
            iconSize: QueryaIconSizes.treeGroup,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.6),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            expanded: _expanded,
            onTap: _toggle,
            connection: widget.connection,
            onContextRefresh: _loadObjects,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (_loading)
                  const ConnectionTreeLoadingRow.nested()
                else if (_error != null)
                  TreeLoadError(
                    title: 'Could not load objects',
                    message: _error!,
                    onRetry: _loadObjects,
                  ),
                if (_loaded && _error == null) ...[
                  _PgObjectGroup(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    objectKind: PostgresObjectKind.table,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefresh: _loadObjects,
                    label: 'Tables',
                    icon: QueryaIcons.tableGroup,
                    itemIcon: QueryaIcons.tableLeaf,
                    items: _tables,
                    onItemTap: widget.onPostgresObjectSelected != null
                        ? (name) => widget.onPostgresObjectSelected!(
                              widget.connection,
                              widget.databaseName,
                              widget.schemaName,
                              name,
                              PostgresObjectKind.table,
                            )
                        : null,
                  ),
                  _PgObjectGroup(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    objectKind: PostgresObjectKind.view,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefresh: _loadObjects,
                    label: 'Views',
                    icon: QueryaIcons.viewGroup,
                    itemIcon: QueryaIcons.viewLeaf,
                    items: _views,
                    onItemTap: widget.onPostgresObjectSelected != null
                        ? (name) => widget.onPostgresObjectSelected!(
                              widget.connection,
                              widget.databaseName,
                              widget.schemaName,
                              name,
                              PostgresObjectKind.view,
                            )
                        : null,
                  ),
                  _PgObjectGroup(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    objectKind: PostgresObjectKind.materializedView,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefresh: _loadObjects,
                    label: 'Materialized views',
                    icon: QueryaIcons.materializedViewGroup,
                    itemIcon: QueryaIcons.materializedViewLeaf,
                    items: _matviews,
                    onItemTap: widget.onPostgresObjectSelected != null
                        ? (name) => widget.onPostgresObjectSelected!(
                              widget.connection,
                              widget.databaseName,
                              widget.schemaName,
                              name,
                              PostgresObjectKind.materializedView,
                            )
                        : null,
                  ),
                  _PgObjectGroup(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    objectKind: PostgresObjectKind.function,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefresh: _loadObjects,
                    label: 'Functions',
                    icon: QueryaIcons.functionGroup,
                    itemIcon: QueryaIcons.functionLeaf,
                    items: _functions,
                    onItemTap: widget.onPostgresObjectSelected != null
                        ? (name) => widget.onPostgresObjectSelected!(
                              widget.connection,
                              widget.databaseName,
                              widget.schemaName,
                              name,
                              PostgresObjectKind.function,
                            )
                        : null,
                  ),
                  _PgObjectGroup(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    objectKind: PostgresObjectKind.sequence,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onRefresh: _loadObjects,
                    label: 'Sequences',
                    icon: QueryaIcons.sequenceGroup,
                    itemIcon: QueryaIcons.sequenceLeaf,
                    items: _sequences,
                    onItemTap: widget.onPostgresObjectSelected != null
                        ? (name) => widget.onPostgresObjectSelected!(
                              widget.connection,
                              widget.databaseName,
                              widget.schemaName,
                              name,
                              PostgresObjectKind.sequence,
                            )
                        : null,
                  ),
                  _PgSchemaToolRow(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    label: 'Indexes',
                    icon: QueryaIcons.indexes,
                    kind: PostgresObjectKind.schemaIndexes,
                    onPostgresObjectSelected: widget.onPostgresObjectSelected,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onContextRefresh: _loadObjects,
                  ),
                  _PgSchemaToolRow(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    label: 'Triggers',
                    icon: QueryaIcons.triggers,
                    kind: PostgresObjectKind.schemaTriggers,
                    onPostgresObjectSelected: widget.onPostgresObjectSelected,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onContextRefresh: _loadObjects,
                  ),
                  _PgSchemaToolRow(
                    connection: widget.connection,
                    databaseName: widget.databaseName,
                    schemaName: widget.schemaName,
                    label: 'Types',
                    icon: QueryaIcons.types,
                    kind: PostgresObjectKind.schemaTypes,
                    onPostgresObjectSelected: widget.onPostgresObjectSelected,
                    onPostgresOpenSqlWorkspace:
                        widget.onPostgresOpenSqlWorkspace,
                    onContextRefresh: _loadObjects,
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

class _PgSchemaToolRow extends material.StatelessWidget {
  const _PgSchemaToolRow({
    required this.connection,
    required this.databaseName,
    required this.schemaName,
    required this.label,
    required this.icon,
    required this.kind,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
    this.onContextRefresh,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String schemaName;
  final String label;
  final material.IconData icon;
  final PostgresObjectKind kind;
  final void Function(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;
  final VoidCallback? onContextRefresh;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.mutedForeground;
    return QueryaTreeIndentGuide(
      depth: 1,
      padding: const material.EdgeInsets.only(top: 2, bottom: 2),
      child: QueryaConnectionTreeRow(
        label: label,
        icon: icon,
        iconSize: QueryaIconSizes.treeGroup,
        iconColor: muted,
        trailing: material.Icon(
          QueryaIcons.expandClosed,
          size: QueryaIconSizes.treeExpand,
          color: muted,
        ),
        onTap: onPostgresObjectSelected == null
            ? null
            : () => onPostgresObjectSelected!(
                  connection,
                  databaseName,
                  schemaName,
                  '',
                  kind,
                ),
        textStyle: material.TextStyle(
          fontSize: 11,
          color: muted,
        ),
        connection: connection,
        onContextRefresh: onContextRefresh,
        onOpenSqlWorkspace: onPostgresOpenSqlWorkspace,
      ),
    );
  }
}

class _PgObjectGroup extends StatefulWidget {
  const _PgObjectGroup({
    required this.connection,
    required this.databaseName,
    required this.schemaName,
    required this.objectKind,
    required this.onRefresh,
    required this.label,
    required this.icon,
    required this.itemIcon,
    required this.items,
    this.onPostgresOpenSqlWorkspace,
    this.onItemTap,
  });

  final ConnectionRow connection;
  final String databaseName;
  final String schemaName;
  final PostgresObjectKind objectKind;
  final VoidCallback onRefresh;
  final String label;
  final material.IconData icon;
  final material.IconData itemIcon;
  final List<String> items;
  final OnPostgresOpenSqlWorkspace? onPostgresOpenSqlWorkspace;
  final void Function(String itemName)? onItemTap;

  @override
  State<_PgObjectGroup> createState() => _PgObjectGroupState();
}

class _PgObjectGroupState extends State<_PgObjectGroup> {
  bool _expanded = false;
  final _filterController = material.TextEditingController();
  String _filter = '';
  final Set<String> _pinnedItems = {};

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _filter.trim().toLowerCase();
    final matching = query.isEmpty
        ? widget.items
        : widget.items.where((it) => it.toLowerCase().contains(query)).toList();
    final sorted = [
      ...matching.where((it) => _pinnedItems.contains(it)),
      ...matching.where((it) => !_pinnedItems.contains(it)),
    ];

    final showFilter = widget.items.length >= 8 || _filter.isNotEmpty;

    return QueryaTreeIndentGuide(
      depth: 1,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          QueryaConnectionTreeRow(
            label: _filter.isEmpty
                ? '${widget.label} (${widget.items.length})'
                : '${widget.label} (${sorted.length}/${widget.items.length})',
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
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            estimatedChildCount: widget.items.length,
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                if (showFilter)
                  TreeObjectFilterBar(
                    controller: _filterController,
                    hintText: 'Filter ${widget.label.toLowerCase()}...',
                    onChanged: (val) => setState(() => _filter = val),
                    onClear: () => setState(() {
                      _filter = '';
                      _filterController.clear();
                    }),
                    filteredCount: sorted.length,
                    totalCount: widget.items.length,
                  ),
                if (sorted.isEmpty && widget.items.isNotEmpty)
                  material.Padding(
                    padding: QueryaTreeTokens.emptyFilterPadding,
                    child: Text('No matching ${widget.label.toLowerCase()}')
                        .muted()
                        .xSmall(),
                  )
                else
                  QueryaTreeIndentGuide(
                    depth: 1,
                    leading: QueryaTreeTokens.leafList - QueryaTreeTokens.indent,
                    child: lazyConnectionTreeList(
                    context: context,
                    itemCount: sorted.length,
                    itemExtent: kConnectionTreeRowExtent,
                    itemBuilder: (context, index) {
                      final item = sorted[index];
                      final isPinned = _pinnedItems.contains(item);
                      return _ConnectionsTreeSelectionBuilder<bool>(
                        select: (sel) =>
                            sel.selectedConnectionId == widget.connection.id &&
                            sel.selectedPostgresObject != null &&
                            sel.selectedPostgresObject!.database ==
                                widget.databaseName &&
                            sel.selectedPostgresObject!.schema ==
                                widget.schemaName &&
                            sel.selectedPostgresObject!.name == item &&
                            sel.selectedPostgresObject!.kind ==
                                widget.objectKind,
                        builder: (context, isSelected) {
                          return QueryaConnectionTreeRow(
                            key: material.ValueKey(
                              'pg-${widget.objectKind.name}-${widget.databaseName}-${widget.schemaName}-$item',
                            ),
                            label: item,
                            isSelected: isSelected,
                            isPinned: isPinned,
                            onTogglePin: () {
                              setState(() {
                                if (isPinned) {
                                  _pinnedItems.remove(item);
                                } else {
                                  _pinnedItems.add(item);
                                }
                              });
                            },
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
                            onContextRefresh: widget.onRefresh,
                            onOpenSqlWorkspace:
                                widget.onPostgresOpenSqlWorkspace,
                            openSqlDatabase: widget.databaseName,
                            openSqlSchema: widget.schemaName,
                            openSqlName: item,
                            openSqlKind: widget.objectKind,
                          );
                        },
                      );
                    },
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
