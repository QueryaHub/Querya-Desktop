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
                            lazyConnectionTreeList(
                              context: context,
                              itemCount: _tables.length,
                              itemExtent: kConnectionTreeRowExtent,
                              padding: const material.EdgeInsets.only(left: 12),
                              itemBuilder: (context, index) {
                                final t = _tables[index];
                                return _PgTreeRow(
                                  key: material.ValueKey(
                                    'sqlite-table-${widget.connection.id ?? 0}-$t',
                                  ),
                                  label: t,
                                  icon: material.Icons.grid_on_rounded,
                                  iconSize: 12,
                                  iconColor: theme.colorScheme.mutedForeground,
                                  textStyle: material.TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.foreground,
                                  ),
                                  verticalPadding: 2,
                                  onTap: widget.onSqliteObjectSelected == null
                                      ? null
                                      : () => widget.onSqliteObjectSelected!(
                                            widget.connection,
                                            t,
                                            SqliteObjectKind.table,
                                          ),
                                  connection: widget.connection,
                                  onContextRefresh: null,
                                  onOpenSqlWorkspace: null,
                                );
                              },
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
                            lazyConnectionTreeList(
                              context: context,
                              itemCount: _views.length,
                              itemExtent: kConnectionTreeRowExtent,
                              padding: const material.EdgeInsets.only(left: 12),
                              itemBuilder: (context, index) {
                                final v = _views[index];
                                return _PgTreeRow(
                                  key: material.ValueKey(
                                    'sqlite-view-${widget.connection.id ?? 0}-$v',
                                  ),
                                  label: v,
                                  icon: material.Icons.grid_on_rounded,
                                  iconSize: 12,
                                  iconColor: theme.colorScheme.mutedForeground,
                                  textStyle: material.TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.foreground,
                                  ),
                                  verticalPadding: 2,
                                  onTap: widget.onSqliteObjectSelected == null
                                      ? null
                                      : () => widget.onSqliteObjectSelected!(
                                            widget.connection,
                                            v,
                                            SqliteObjectKind.view,
                                          ),
                                  connection: widget.connection,
                                  onContextRefresh: null,
                                  onOpenSqlWorkspace: null,
                                );
                              },
                            ),
                          ],
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
