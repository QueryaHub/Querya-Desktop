part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── PostgreSQL connection tile with expandable database tree ────────────────

class _PostgresConnectionTile extends StatefulWidget {
  const _PostgresConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onPostgresObjectSelected,
    this.onPostgresOpenSqlWorkspace,
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
    String schema,
    String name,
    PostgresObjectKind kind,
  )? onPostgresObjectSelected;
  final void Function(ConnectionRow connection)? onPostgresOpenSqlWorkspace;

  @override
  State<_PostgresConnectionTile> createState() =>
      _PostgresConnectionTileState();
}

class _PostgresConnectionTileState extends State<_PostgresConnectionTile> {
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
    PgLease? lease;
    try {
      final c = widget.connection;
      lease = await PostgresService.instance.acquire(
        c,
        database: c.databaseName ?? 'postgres',
        mode: PgSessionMode.readOnly,
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
                _PgDatabasesNode(
                  connection: widget.connection,
                  databases: _databases,
                  onPostgresObjectSelected: widget.onPostgresObjectSelected,
                  onPostgresOpenSqlWorkspace: widget.onPostgresOpenSqlWorkspace,
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
