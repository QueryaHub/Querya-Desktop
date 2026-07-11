part of 'package:querya_desktop/features/connections/connections_panel.dart';

/// Expandable sidebar tile for an installed extension database driver.
class _ExtensionConnectionTile extends StatefulWidget {
  const _ExtensionConnectionTile({
    required this.connection,
    this.isSelected = false,
    required this.icon,
    this.iconAsset,
    required this.onRemove,
    this.onTap,
    this.isExpanded = false,
    this.onExpandedChanged,
  });

  final ConnectionRow connection;
  final bool isSelected;
  final material.IconData icon;
  final String? iconAsset;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
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

  @override
  void initState() {
    super.initState();
    if (widget.isExpanded) {
      _loadTree();
    }
  }

  @override
  void didUpdateWidget(_ExtensionConnectionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded && !oldWidget.isExpanded) {
      if (_schema == null && !_loading) {
        _loadTree();
      }
    } else if (!widget.isExpanded && oldWidget.isExpanded) {
      setState(() {
        _schema = null;
        _loading = false;
        _error = null;
      });
    }
  }

  void _toggle() {
    widget.onExpandedChanged?.call(!widget.isExpanded);
  }

  Future<void> _loadTree() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schema =
          await ExtensionDriverSession.instance.getSchemaTree(widget.connection);
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
        : material.Icon(
            widget.icon,
            size: 16,
            color: theme.colorScheme.primary,
          );

    return material.Padding(
      padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _sidebarConnectionShell(
            context: context,
            isSelected: widget.isSelected,
            onTap: widget.onTap,
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              child: material.Row(
                children: [
                  material.GestureDetector(
                    onTap: _toggle,
                    behavior: material.HitTestBehavior.opaque,
                    child: material.AnimatedRotation(
                      turns: widget.isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: material.Icon(
                        material.Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                  const Gap(4),
                  iconWidget,
                  const Gap(8),
                  material.Expanded(
                    child: material.Text(
                      widget.connection.name,
                      overflow: material.TextOverflow.ellipsis,
                      style: material.TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isSelected
                            ? material.FontWeight.w600
                            : material.FontWeight.w500,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  material.Tooltip(
                    message: 'Remove',
                    child: material.InkWell(
                      onTap: widget.onRemove,
                      borderRadius: material.BorderRadius.circular(6),
                      child: material.Padding(
                        padding: const material.EdgeInsets.all(4),
                        child: material.Icon(
                          material.Icons.close_rounded,
                          size: 14,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded) ...[
            if (_loading)
              const material.Padding(
                padding: material.EdgeInsets.fromLTRB(36, 8, 8, 8),
                child: material.SizedBox(
                  width: 16,
                  height: 16,
                  child: material.CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              material.Padding(
                padding: const material.EdgeInsets.fromLTRB(28, 4, 8, 8),
                child: material.SelectableText(
                  _error!,
                  style: material.TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.destructive,
                  ),
                ),
              )
            else if (_schema != null)
              material.Padding(
                padding: const material.EdgeInsets.only(left: 20),
                child: SduiTreeBuilder(
                  schema: _schema!,
                  fetchChildren: _fetchChildren,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
