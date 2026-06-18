part of 'package:querya_desktop/features/connections/connections_panel.dart';

enum SqliteObjectKind {
  table,
  view,
}

class _SqliteConnectionTile extends StatefulWidget {
  const _SqliteConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onSqliteObjectSelected,
    this.onSqliteOpenSqlWorkspace,
  });

  final ConnectionRow connection;
  final bool isSelected;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(
    ConnectionRow connection,
    String name,
    SqliteObjectKind kind,
  )? onSqliteObjectSelected;
  final void Function(ConnectionRow connection)? onSqliteOpenSqlWorkspace;

  @override
  State<_SqliteConnectionTile> createState() => _SqliteConnectionTileState();
}

class _SqliteConnectionTileState extends State<_SqliteConnectionTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    SqliteLease? lease;
    try {
      lease = await SqliteService.instance.acquire(
        widget.connection,
        mode: SqliteSessionMode.readOnly,
      );
      final tables = await lease.connection.listTables();
      final views = await lease.connection.listViews();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _views = views;
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
        : material.Icon(widget.icon,
            size: 16, color: theme.colorScheme.primary);

    return ContextMenu(
      items: [
        MenuButton(
          leading: material.Icon(material.Icons.refresh_rounded,
              size: 18, color: theme.colorScheme.mutedForeground),
          onPressed: (_) {
            setState(() {
              _tables = [];
              _views = [];
            });
            _loadTables();
          },
          child: const Text('Refresh database'),
        ),
        if (widget.onSqliteOpenSqlWorkspace != null)
          MenuButton(
            leading: material.Icon(material.Icons.terminal_rounded,
                size: 18, color: theme.colorScheme.mutedForeground),
            onPressed: (_) =>
                widget.onSqliteOpenSqlWorkspace!(widget.connection),
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
                        duration: context.motionDuration(QueryaMotion.fast),
                        curve: context.motionCurve(QueryaMotion.standardCurve),
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
                                    widget.connection.host!,
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
                    material.Padding(
                      padding: const material.EdgeInsets.only(
                          left: 28, top: 4, bottom: 4),
                      child: material.Text(
                        'Error loading schema',
                        overflow: material.TextOverflow.ellipsis,
                        maxLines: 1,
                        style: material.TextStyle(
                            fontSize: 11, color: theme.colorScheme.destructive),
                      ),
                    ),
                  if (!_loading && _error == null)
                    material.Padding(
                      padding: const material.EdgeInsets.only(left: 16),
                      child: material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          if (_tables.isNotEmpty)
                            _SqliteObjectGroup(
                              connection: widget.connection,
                              objectKind: SqliteObjectKind.table,
                              onRefresh: _loadTables,
                              label: 'Tables',
                              icon: material.Icons.table_chart_rounded,
                              itemIcon: material.Icons.grid_on_rounded,
                              items: _tables,
                              onItemTap: widget.onSqliteObjectSelected == null
                                  ? null
                                  : (name) => widget.onSqliteObjectSelected!(
                                        widget.connection,
                                        name,
                                        SqliteObjectKind.table,
                                      ),
                            ),
                          if (_views.isNotEmpty)
                            _SqliteObjectGroup(
                              connection: widget.connection,
                              objectKind: SqliteObjectKind.view,
                              onRefresh: _loadTables,
                              label: 'Views',
                              icon: material.Icons.view_agenda_rounded,
                              itemIcon: material.Icons.view_week_rounded,
                              items: _views,
                              onItemTap: widget.onSqliteObjectSelected == null
                                  ? null
                                  : (name) => widget.onSqliteObjectSelected!(
                                        widget.connection,
                                        name,
                                        SqliteObjectKind.view,
                                      ),
                            ),
                          if (_tables.isEmpty && _views.isEmpty)
                            material.Padding(
                              padding: const material.EdgeInsets.only(
                                  left: 12, top: 4, bottom: 4),
                              child: const Text('Database is empty')
                                  .muted()
                                  .xSmall(),
                            ),
                        ],
                      ),
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

class _SqliteObjectGroup extends StatefulWidget {
  const _SqliteObjectGroup({
    required this.connection,
    required this.objectKind,
    required this.onRefresh,
    required this.label,
    required this.icon,
    required this.itemIcon,
    required this.items,
    this.onItemTap,
  });

  final ConnectionRow connection;
  final SqliteObjectKind objectKind;
  final VoidCallback onRefresh;
  final String label;
  final material.IconData icon;
  final material.IconData itemIcon;
  final List<String> items;
  final void Function(String itemName)? onItemTap;

  @override
  State<_SqliteObjectGroup> createState() => _SqliteObjectGroupState();
}

class _SqliteObjectGroupState extends State<_SqliteObjectGroup> {
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
              duration: context.motionDuration(QueryaMotion.fast),
              curve: context.motionCurve(QueryaMotion.standardCurve),
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
          ),
          QueryaAnimatedExpand(
            expanded: _expanded,
            child: lazyConnectionTreeList(
              context: context,
              itemCount: widget.items.length,
              itemExtent: kConnectionTreeRowExtent,
              padding: const material.EdgeInsets.only(left: 22),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return _PgTreeRow(
                  key: material.ValueKey(
                    'sqlite-${widget.objectKind.name}-$item',
                  ),
                  label: item,
                  icon: widget.itemIcon,
                  iconSize: 12,
                  iconColor: theme.colorScheme.mutedForeground,
                  textStyle: material.TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.foreground,
                  ),
                  verticalPadding: 2,
                  onTap: widget.onItemTap != null
                      ? () => widget.onItemTap!(item)
                      : null,
                  connection: widget.connection,
                  onContextRefresh: null,
                  onOpenSqlWorkspace: null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
