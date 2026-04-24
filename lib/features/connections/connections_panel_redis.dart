part of 'package:querya_desktop/features/connections/connections_panel.dart';

// ─── Redis connection tile with expandable database tree ────────────────────

class _RedisConnectionTile extends StatefulWidget {
  const _RedisConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.onDatabaseTap,
  });

  final ConnectionRow connection;
  final bool isSelected;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  final void Function(int database)? onDatabaseTap;

  @override
  State<_RedisConnectionTile> createState() => _RedisConnectionTileState();
}

class _RedisConnectionTileState extends State<_RedisConnectionTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  // All 16 databases (db0–db15) with key counts
  List<({int index, int keys})> _databases = [];

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
            // Connection row
            material.Row(
              children: [
                // Expand/collapse arrow
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
            if (_expanded) ...[
              if (_loading)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Row(
                    children: [
                      const material.SizedBox(
                        width: 12,
                        height: 12,
                        child: material.CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const Gap(8),
                      const Text('Loading...').muted().xSmall(),
                    ],
                  ),
                ),
              if (_error != null)
                material.Padding(
                  padding: const material.EdgeInsets.only(left: 28, top: 4, bottom: 4),
                  child: material.Text(
                    'Error',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                        fontSize: 11, color: theme.colorScheme.destructive),
                  ),
                ),
              for (final db in _databases)
                _RedisDatabaseNode(
                  index: db.index,
                  keys: db.keys,
                  onTap: () => widget.onDatabaseTap?.call(db.index),
                ),
            ],
          ],
        ),
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
      padding: const material.EdgeInsets.only(left: 24),
      child: material.MouseRegion(
        cursor: material.SystemMouseCursors.click,
        child: material.InkWell(
          onTap: onTap,
          borderRadius: material.BorderRadius.circular(6),
          child: material.Padding(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            child: material.Row(
              children: [
                material.Icon(
                  material.Icons.dns_rounded,
                  size: 14,
                  color: keys > 0
                      ? theme.colorScheme.primary.withValues(alpha: 0.7)
                      : theme.colorScheme.mutedForeground.withValues(alpha: 0.5),
                ),
                const Gap(8),
                material.Expanded(
                  child: material.Text(
                    'db$index',
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                      fontSize: 12,
                      color: keys > 0
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                if (keys > 0)
                  material.Text(
                    '$keys',
                    style: material.TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.mutedForeground),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
