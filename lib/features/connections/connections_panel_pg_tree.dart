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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
  final VoidCallback onRefreshDatabases;

  @override
  State<_PgDatabasesNode> createState() => _PgDatabasesNodeState();
}

/// Ellipsis label; tooltip only when text overflows (intrinsic width > slot).
class _PgTreeRowLabel extends material.StatelessWidget {
  const _PgTreeRowLabel({
    required this.label,
    required this.textStyle,
  });

  final String label;
  final material.TextStyle textStyle;

  @override
  material.Widget build(material.BuildContext context) {
    return material.LayoutBuilder(
      builder: (context, constraints) {
        final tp = material.TextPainter(
          text: material.TextSpan(text: label, style: textStyle),
          maxLines: 1,
          textDirection: material.TextDirection.ltr,
        );
        tp.layout(maxWidth: double.infinity);
        final overflow = tp.width > constraints.maxWidth + 0.5;
        final text = material.Text(
          label,
          overflow: material.TextOverflow.ellipsis,
          maxLines: 1,
          style: textStyle,
        );
        if (!overflow) return text;
        return material.Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 450),
          child: text,
        );
      },
    );
  }
}

/// Shared tree row: consistent ink hover, optional context menu, tooltips when truncated.
class _PgTreeRow extends material.StatelessWidget {
  const _PgTreeRow({
    required this.label,
    this.leading,
    this.icon,
    this.iconSize = 13,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.verticalPadding = 3,
    required this.textStyle,
    this.connection,
    this.onContextRefresh,
    this.onOpenSqlWorkspace,
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
  final double verticalPadding;
  final material.TextStyle textStyle;
  final ConnectionRow? connection;
  final VoidCallback? onContextRefresh;
  final void Function(ConnectionRow connection)? onOpenSqlWorkspace;
  final VoidCallback? onContextDelete;
  final String? contextDeleteLabel;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final row = material.Material(
      color: material.Colors.transparent,
      child: material.InkWell(
        onTap: onTap,
        borderRadius: material.BorderRadius.circular(4),
        hoverColor: primary.withValues(alpha: 0.07),
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
    );
    if (connection == null) return row;
    return ContextMenu(
      items: [
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
        if (onOpenSqlWorkspace != null)
          MenuButton(
            leading: material.Icon(
              material.Icons.terminal_rounded,
              size: 18,
              color: theme.colorScheme.mutedForeground,
            ),
            onPressed: (_) => onOpenSqlWorkspace!(connection!),
            child: const Text('Open in SQL'),
          ),
        if (onContextDelete != null)
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
      child: row,
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
              duration: const Duration(milliseconds: 100),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.dns_rounded,
            iconSize: 14,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.7),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            verticalPadding: 4,
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshDatabases,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final db in widget.databases)
              _PgDatabaseNode(
                key: material.ValueKey('pg-db-${widget.connection.id ?? 0}-$db'),
                connection: widget.connection,
                databaseName: db,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

  @override
  State<_PgDatabaseNode> createState() => _PgDatabaseNodeState();
}

class _PgDatabaseNodeState extends State<_PgDatabaseNode> {
  bool _expanded = false;
  bool _loading = false;
  List<String> _schemas = [];

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _schemas.isEmpty && !_loading) {
      _loadSchemas();
    }
  }

  Future<void> _loadSchemas() async {
    if (!mounted) return;
    setState(() => _loading = true);
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
            onContextRefresh: _loadSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded) ...[
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Extensions',
              icon: material.Icons.extension_rounded,
              kind: PostgresObjectKind.databaseExtensions,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
              onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
              onContextRefresh: _loadSchemas,
            ),
            _PgDbToolRow(
              connection: widget.connection,
              databaseName: widget.databaseName,
              label: 'Foreign data',
              icon: material.Icons.public_rounded,
              kind: PostgresObjectKind.databaseForeignData,
              onPostgresObjectSelected: widget.onPostgresObjectSelected,
              onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
              onContextRefresh: _loadSchemas,
            ),
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
            if (_schemas.isNotEmpty)
              _PgSchemasNode(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemas: _schemas,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefreshSchemas: _loadSchemas,
              ),
          ],
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
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
        iconSize: 13,
        iconColor: muted,
        trailing: material.Icon(
          material.Icons.chevron_right_rounded,
          size: 13,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
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
              duration: const Duration(milliseconds: 100),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.account_tree_rounded,
            iconSize: 13,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefreshSchemas,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final schema in widget.schemas)
              _PgSchemaNode(
                key: material.ValueKey(
                  'pg-schema-${widget.connection.id ?? 0}-${widget.databaseName}-$schema',
                ),
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: schema,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

  @override
  State<_PgSchemaNode> createState() => _PgSchemaNodeState();
}

class _PgSchemaNodeState extends State<_PgSchemaNode> {
  bool _expanded = false;
  bool _loading = false;
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
    setState(() => _loading = true);
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
        matviews =
            await conn.listMaterializedViews(schema: widget.schemaName);
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
      padding: const material.EdgeInsets.only(left: 12),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          _PgTreeRow(
            label: widget.schemaName,
            leading: material.AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 100),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 14,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: material.Icons.diamond_outlined,
            iconSize: 13,
            iconColor: theme.colorScheme.primary.withValues(alpha: 0.6),
            textStyle: material.TextStyle(
              fontSize: 12,
              color: theme.colorScheme.foreground,
            ),
            onTap: _toggle,
            connection: widget.connection,
            onContextRefresh: _loadObjects,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
            if (_loaded) ...[
              _PgObjectGroup(
                connection: widget.connection,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
                label: 'Tables',
                icon: material.Icons.table_chart_rounded,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
                label: 'Views',
                icon: material.Icons.view_agenda_rounded,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
                label: 'Materialized views',
                icon: material.Icons.dynamic_feed_rounded,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
                label: 'Functions',
                icon: material.Icons.functions_rounded,
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
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onRefresh: _loadObjects,
                label: 'Sequences',
                icon: material.Icons.format_list_numbered_rounded,
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
                icon: material.Icons.table_rows_rounded,
                kind: PostgresObjectKind.schemaIndexes,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Triggers',
                icon: material.Icons.bolt_rounded,
                kind: PostgresObjectKind.schemaTriggers,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
              ),
              _PgSchemaToolRow(
                connection: widget.connection,
                databaseName: widget.databaseName,
                schemaName: widget.schemaName,
                label: 'Types',
                icon: material.Icons.category_rounded,
                kind: PostgresObjectKind.schemaTypes,
                onPostgresObjectSelected: widget.onPostgresObjectSelected,
                onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
                onContextRefresh: _loadObjects,
              ),
            ],
          ],
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
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
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
        iconSize: 13,
        iconColor: muted,
        trailing: material.Icon(
          material.Icons.chevron_right_rounded,
          size: 13,
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
    required this.onRefresh,
    required this.label,
    required this.icon,
    required this.items,
    this.onPostgresOpenSqlWorkspace,
    this.onItemTap,
  });

  final ConnectionRow connection;
  final VoidCallback onRefresh;
  final String label;
  final material.IconData icon;
  final List<String> items;
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;
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
              duration: const Duration(milliseconds: 100),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 13,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            icon: widget.icon,
            iconSize: 13,
            iconColor: theme.colorScheme.mutedForeground,
            textStyle: material.TextStyle(
              fontSize: 11,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            connection: widget.connection,
            onContextRefresh: widget.onRefresh,
            onOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
          ),
          if (_expanded)
            for (final item in widget.items)
              material.Padding(
                padding: const material.EdgeInsets.only(left: 22),
                child: _PgTreeRow(
                  label: item,
                  icon: widget.icon,
                  iconSize: 12,
                  iconColor:
                      theme.colorScheme.primary.withValues(alpha: 0.5),
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
                ),
              ),
        ],
      ),
    );
  }
}
