part of 'package:querya_desktop/features/connections/connections_panel.dart';

class _PgDatabasesNode extends StatefulWidget {
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
  State<_PgDatabasesNode> createState() => _PgDatabasesNodeState();
}

/// Ellipsis label; tooltip when the name is long enough to likely truncate.
class _PgTreeRowLabel extends material.StatelessWidget {
  const _PgTreeRowLabel({
    required this.label,
    required this.textStyle,
  });

  final String label;
  final material.TextStyle textStyle;

  static const int _tooltipMinLength = 28;

  @override
  material.Widget build(material.BuildContext context) {
    final text = material.Text(
      label,
      overflow: material.TextOverflow.ellipsis,
      maxLines: 1,
      style: textStyle,
    );
    if (label.length < _tooltipMinLength) return text;
    return material.Tooltip(
      message: label,
      waitDuration: kQueryaTooltipWait,
      child: text,
    );
  }
}

/// Shared tree row: consistent ink hover, optional context menu, tooltips when truncated.
class _PgTreeRow extends material.StatelessWidget {
  const _PgTreeRow({
    super.key,
    required this.label,
    this.leading,
    this.icon,
    this.iconSize = QueryaIconSizes.treeGroup,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.expanded,
    this.verticalPadding = 3,
    required this.textStyle,
    this.connection,
    this.onContextRefresh,
    this.onOpenSqlWorkspace,
    this.openSqlDatabase,
    this.openSqlSchema,
    this.openSqlName,
    this.openSqlKind,
    this.onContextDelete,
    this.contextDeleteLabel,
  });

  final String label;
  final material.Widget? leading;
  final material.IconData? icon;
  final double iconSize;
  final material.Color? iconColor;
  final material.Widget? trailing;
  final void Function()? onTap;

  /// When non-null, row is an expand control ([Semantics.button] + expanded).
  final bool? expanded;
  final double verticalPadding;
  final material.TextStyle textStyle;
  final ConnectionRow? connection;
  final VoidCallback? onContextRefresh;
  final OnPostgresOpenSqlWorkspace? onOpenSqlWorkspace;
  final String? openSqlDatabase;
  final String? openSqlSchema;
  final String? openSqlName;
  final PostgresObjectKind? openSqlKind;
  final VoidCallback? onContextDelete;
  final String? contextDeleteLabel;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final row = material.CallbackShortcuts(
      bindings: {
        if (expanded == false && onTap != null)
          const material.SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              onTap!(),
        if (expanded == true && onTap != null)
          const material.SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              onTap!(),
      },
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          onTap: onTap,
          canRequestFocus: onTap != null,
          borderRadius: material.BorderRadius.circular(4),
          hoverColor: primary.withValues(alpha: 0.07),
          focusColor: primary.withValues(alpha: 0.14),
          splashColor: primary.withValues(alpha: 0.10),
          highlightColor: primary.withValues(alpha: 0.05),
          mouseCursor: onTap != null
              ? material.SystemMouseCursors.click
              : material.SystemMouseCursors.basic,
          child: material.Padding(
            padding: material.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: verticalPadding,
            ),
            child: material.Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const Gap(4),
                ],
                if (icon != null) ...[
                  material.Icon(
                    icon,
                    size: iconSize,
                    color: iconColor ?? muted,
                  ),
                  const Gap(6),
                ],
                material.Expanded(
                  child: _PgTreeRowLabel(label: label, textStyle: textStyle),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
    if (connection == null) {
      return expanded == null
          ? row
          : material.Semantics(
              button: true,
              expanded: expanded,
              child: row,
            );
    }
    final menu = ContextMenu(
      items: [
        if (openSqlName != null) ...[
          MenuButton(
            leading: material.Icon(
              material.Icons.table_rows_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            onPressed: (_) {
              final qualified = openSqlSchema != null && openSqlSchema!.isNotEmpty
                  ? '"$openSqlSchema"."$openSqlName"'
                  : '"$openSqlName"';
              Clipboard.setData(
                ClipboardData(text: 'SELECT * FROM $qualified LIMIT 100;'),
              );
              if (onOpenSqlWorkspace != null && connection != null) {
                onOpenSqlWorkspace!(
                  connection!,
                  database: openSqlDatabase,
                  schema: openSqlSchema,
                  name: openSqlName,
                  kind: openSqlKind,
                );
              }
            },
            child: const Text('Select TOP 100'),
          ),
          MenuButton(
            leading: material.Icon(
              material.Icons.code_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) {
              final qualified = openSqlSchema != null && openSqlSchema!.isNotEmpty
                  ? '"$openSqlSchema"."$openSqlName"'
                  : '"$openSqlName"';
              Clipboard.setData(ClipboardData(text: 'SELECT * FROM $qualified;'));
            },
            child: const Text('Copy SELECT statement'),
          ),
          const MenuDivider(),
        ],
        if (onContextRefresh != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.refresh_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onContextRefresh!(),
            child: const Text('Refresh'),
          ),
        MenuButton(
          leading: material.Icon(
            material.Icons.copy_rounded,
            size: 18,
            color: theme.colorScheme.mutedForeground,
          ),
          onPressed: (_) {
            Clipboard.setData(ClipboardData(text: label));
          },
          child: const Text('Copy name'),
        ),
        if (onOpenSqlWorkspace != null && openSqlName == null)
          MenuButton(
            leading: material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onOpenSqlWorkspace!(
              connection!,
              database: openSqlDatabase,
              schema: openSqlSchema,
              name: openSqlName,
              kind: openSqlKind,
            ),
            child: const Text('Open in SQL'),
          ),
        if (onContextDelete != null) ...[
          const MenuDivider(),
          MenuButton(
            leading: material.Icon(
              material.Icons.delete_outline_rounded,
              size: 18,
              color: theme.colorScheme.destructive,
            ),
            onPressed: (_) => onContextDelete!(),
            child: Text(contextDeleteLabel ?? 'Delete'),
          ),
        ],
      ],
      child: row,
    );
    if (expanded == null) return menu;
    return material.Semantics(
      button: true,
      expanded: expanded,
      child: menu,
    );
  }
}

class _PgDatabasesNodeState extends State<_PgDatabasesNode> {
  bool _expanded = true;

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
            label: 'Databases (${widget.databases.length})',
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
            icon: QueryaIcons.databasesFolder,
            iconSize: QueryaIconSizes.treeConnection,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshDatabases,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: lazyConnectionTreeList(
              context: context,
              itemCount: widget.databases.length,
              itemBuilder: (context, index) {
                final db = widget.databases[index];
                return _PgDatabaseNode(
                  key: material.ValueKey(
                      'pg-db-${widget.connection.id ?? 0}-$db'),
                  connection: widget.connection,
                  databaseName: db,
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
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: _PgTreeRow(
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
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          _PgTreeRow(
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
    return material.Padding(
      padding: const material.EdgeInsets.only(left: QueryaTreeTokens.indent),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          _PgTreeRow(
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
    return material.Padding(
      padding: const material.EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: _PgTreeRow(
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
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
                return _PgTreeRow(
                  key: material.ValueKey(
                    'pg-${widget.objectKind.name}-${widget.databaseName}-${widget.schemaName}-$item',
                  ),
                  label: item,
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
                  onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                  openSqlDatabase: widget.databaseName,
                  openSqlSchema: widget.schemaName,
                  openSqlName: item,
                  openSqlKind: widget.objectKind,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
