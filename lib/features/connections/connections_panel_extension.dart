part of 'package:querya_desktop/features/connections/connections_panel.dart';

/// Expandable sidebar tile for an installed extension database driver.
class _ExtensionConnectionTile extends StatefulWidget {
  const _ExtensionConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    required this.onEdit,
    this.onTap,
    this.onObjectSelected,
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

  /// Fires when a table/view node is clicked in the schema tree.
  final void Function(
    ConnectionRow connection,
    String database,
    String name,
  )? onObjectSelected;
  final bool isExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<_ExtensionConnectionTile> createState() =>
      _ExtensionConnectionTileState();
}

class _ExtensionConnectionTileState extends State<_ExtensionConnectionTile> {
  bool _loading = false;
  String? _error;
  SduiTreeSchema? _schema;
  String? _iconFilePath;

  @override
  void initState() {
    super.initState();
    _resolveIconFile();
    if (widget.isExpanded) {
      _loadTree();
    }
  }

  Future<void> _resolveIconFile() async {
    await LocalExtensionRegistry.instance.load();
    if (!mounted) return;
    final path =
        ExtensionDriverCatalog.iconFileForConnection(widget.connection);
    if (path != null) {
      setState(() => _iconFilePath = path);
    }
  }

  @override
  void didUpdateWidget(_ExtensionConnectionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connection.extensionId != oldWidget.connection.extensionId ||
        widget.connection.type != oldWidget.connection.type) {
      _resolveIconFile();
    }
    if (widget.isExpanded && !oldWidget.isExpanded) {
      if (_schema == null && !_loading) {
        _loadTree();
      }
    }
  }

  void _toggle() {
    final next = !widget.isExpanded;
    widget.onExpandedChanged?.call(next);
    if (next) {
      // Opening the schema tree should activate this connection in the workspace
      // (SQL editor / table view), same as clicking the connection row.
      widget.onTap?.call();
    }
  }

  Future<void> _loadTree() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema = await ExtensionDriverSession.instance
          .getSchemaTree(widget.connection);
      if (!mounted) return;
      setState(() {
        _schema = schema;
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

  Future<List<SduiTreeNode>> _fetchChildren(String nodeId) {
    return ExtensionDriverSession.instance
        .expandTreeNode(widget.connection, nodeId);
  }

  /// Node ids follow `<kind>.<database>.<name>` (e.g. `table.analytics.events`).
  void _onNodeSelected(SduiTreeNode node) {
    final callback = widget.onObjectSelected;
    if (callback == null) return;
    final parts = node.id.split('.');
    if (parts.length < 3) return;
    final kind = parts[0];
    const tableLikeKinds = {
      'table',
      'view',
      'dict',
      'dictionary',
      'materialized-view',
      'mv'
    };
    if (!tableLikeKinds.contains(kind)) return;
    final database = parts[1];
    final name = parts.sublist(2).join('.');
    if (database.isEmpty || name.isEmpty) return;
    callback(widget.connection, database, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _ConnectionsTreeSelectionScope.of(context);
    final selectedExt = (sel != null &&
            sel.selectedConnectionId == widget.connection.id)
        ? sel.selectedExtensionObject
        : null;
    final material.Widget iconWidget;
    if (_iconFilePath != null) {
      iconWidget = DriverIconImage(
        path: _iconFilePath!,
        size: QueryaIconSizes.sidebarConnectionIcon,
        fallbackIcon: widget.icon,
      );
    } else if (widget.iconAsset != null) {
      iconWidget = material.Image.asset(
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
      );
    } else {
      iconWidget = material.Icon(
        widget.icon,
        size: QueryaIconSizes.sidebarConnectionIcon,
        color: theme.colorScheme.primary,
      );
    }

    return ContextMenu(
      items: [
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
                    expanded: widget.isExpanded,
                    child: material.InkWell(
                      onTap: _toggle,
                      borderRadius: material.BorderRadius.circular(4),
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(2),
                        child: material.AnimatedRotation(
                          turns: widget.isExpanded ? 0.25 : 0,
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
                        horizontal: 4,
                        vertical: 6,
                      ),
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
                                    fontWeight: widget.isSelected
                                        ? material.FontWeight.w600
                                        : material.FontWeight.w500,
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
              expanded: widget.isExpanded,
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  if (_loading)
                    material.Padding(
                      padding: const material.EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 4,
                      ),
                      child: material.Row(
                        children: [
                          const material.SizedBox(
                            width: 12,
                            height: 12,
                            child: material.CircularProgressIndicator(
                              strokeWidth: 1.5,
                            ),
                          ),
                          const Gap(8),
                          const Text('Loading...').muted().xSmall(),
                        ],
                      ),
                    )
                  else if (_error != null)
                    TreeLoadError(
                      title: 'Could not load extension tree',
                      message: _error!,
                      padding: const material.EdgeInsets.only(
                        left: 28,
                        top: 4,
                        bottom: 8,
                      ),
                      onRetry: _loadTree,
                    )
                  else if (_schema != null)
                    material.Padding(
                      padding: const material.EdgeInsets.only(left: 20),
                      child: _schema!.roots.isEmpty
                          ? material.Padding(
                              padding: const material.EdgeInsets.fromLTRB(
                                  0, 8, 8, 8),
                              child: const Text(
                                'No databases found on this server.',
                              ).muted().small(),
                            )
                          : SduiTreeBuilder(
                              schema: _schema!,
                              fetchChildren: _fetchChildren,
                              onNodeSelected: _onNodeSelected,
                              isNodeSelected: selectedExt == null
                                  ? null
                                  : (node) {
                                      final metaDb = node.meta['database'] ??
                                          node.meta['db'];
                                      final metaName = node.meta['table'] ??
                                          node.meta['tableName'] ??
                                          node.meta['name'];
                                      if (metaDb != null && metaName != null) {
                                        if (metaDb == selectedExt.database &&
                                            metaName == selectedExt.name) {
                                          return true;
                                        }
                                      }
                                      final parts = node.id.split('.');
                                      if (parts.length >= 3) {
                                        final db = parts[1];
                                        final name = parts.sublist(2).join('.');
                                        return db == selectedExt.database &&
                                            name == selectedExt.name;
                                      }
                                      return false;
                                    },
                              maxHeight: kConnectionTreeMaxVisibleRows *
                                  kConnectionTreeRowExtent,
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
