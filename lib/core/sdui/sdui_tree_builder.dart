import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders a sidebar-style tree from an SDUI schema with lazy expansion.
///
/// Visible rows are flattened into a [ListView.builder] so only viewport
/// rows are built (large schemas no longer create a full widget Column).
class SduiTreeBuilder extends material.StatefulWidget {
  const SduiTreeBuilder({
    super.key,
    required this.schema,
    this.fetchChildren,
    this.onNodeSelected,
    this.maxHeight,
  });

  final SduiTreeSchema schema;
  final SduiFetchTreeChildren? fetchChildren;
  final void Function(SduiTreeNode node)? onNodeSelected;

  /// When set, the tree scrolls inside a height cap (sidebar use).
  final double? maxHeight;

  @override
  material.State<SduiTreeBuilder> createState() => SduiTreeBuilderState();
}

class _VisibleRow {
  const _VisibleRow.node(this.node, this.depth)
      : error = null,
        isError = false;

  const _VisibleRow.error(this.error, this.depth)
      : node = null,
        isError = true;

  final SduiTreeNode? node;
  final int depth;
  final String? error;
  final bool isError;
}

class SduiTreeBuilderState extends material.State<SduiTreeBuilder> {
  late List<SduiTreeNode> _roots;
  final Set<String> _loading = {};
  final Set<String> _loaded = {};
  final Set<String> _expanded = {};
  final Map<String, String> _expandErrors = {};

  static const double _rowExtent = 36;

  @override
  void initState() {
    super.initState();
    _roots = List<SduiTreeNode>.from(widget.schema.roots);
  }

  @override
  void didUpdateWidget(covariant SduiTreeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema != widget.schema) {
      _roots = List<SduiTreeNode>.from(widget.schema.roots);
      _loading.clear();
      _loaded.clear();
      _expanded.clear();
      _expandErrors.clear();
    }
  }

  Future<void> _onExpand(SduiTreeNode node) async {
    setState(() {
      _expanded.add(node.id);
      _expandErrors.remove(node.id);
    });
    if (!node.expandable || _loaded.contains(node.id) || node.hasChildren) {
      return;
    }
    final fetch = widget.fetchChildren;
    if (fetch == null) return;

    setState(() => _loading.add(node.id));
    try {
      final children = await fetch(node.id);
      if (!mounted) return;
      setState(() {
        _roots = _replaceNode(
          _roots,
          node.id,
          (n) => n.copyWith(children: children),
        );
        _loaded.add(node.id);
        _loading.remove(node.id);
        if (children.isEmpty) {
          _expandErrors[node.id] = 'No child objects found.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading.remove(node.id);
        _expandErrors[node.id] = e.toString();
      });
    }
  }

  void _onCollapse(SduiTreeNode node) {
    setState(() => _expanded.remove(node.id));
  }

  List<SduiTreeNode> _replaceNode(
    List<SduiTreeNode> nodes,
    String id,
    SduiTreeNode Function(SduiTreeNode) update,
  ) {
    return [
      for (final node in nodes)
        if (node.id == id)
          update(node)
        else if (node.children.isNotEmpty)
          node.copyWith(children: _replaceNode(node.children, id, update))
        else
          node,
    ];
  }

  List<_VisibleRow> _flattenVisible() {
    final out = <_VisibleRow>[];
    void walk(SduiTreeNode node, int depth) {
      out.add(_VisibleRow.node(node, depth));
      if (!_expanded.contains(node.id)) return;
      final err = _expandErrors[node.id];
      if (err != null) {
        out.add(_VisibleRow.error(err, depth));
      }
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final root in _roots) {
      walk(root, 0);
    }
    return out;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final rows = _flattenVisible();
    final list = material.ListView.builder(
      shrinkWrap: widget.maxHeight == null,
      physics: widget.maxHeight == null
          ? const material.NeverScrollableScrollPhysics()
          : const material.ClampingScrollPhysics(),
      itemExtent: _rowExtent,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isError) {
          return material.Padding(
            padding: material.EdgeInsets.only(left: 36.0 + row.depth * 16.0),
            child: material.Align(
              alignment: material.Alignment.centerLeft,
              child: Text(row.error!).muted().xSmall(),
            ),
          );
        }
        return _buildNodeRow(row.node!, depth: row.depth);
      },
    );

    if (widget.maxHeight == null) return list;

    return material.ConstrainedBox(
      constraints: material.BoxConstraints(maxHeight: widget.maxHeight!),
      child: list,
    );
  }

  material.Widget _buildNodeRow(SduiTreeNode node, {required int depth}) {
    final canExpand = node.expandable || node.hasChildren;
    final isExpanded = _expanded.contains(node.id);
    final isLoading = _loading.contains(node.id);
    final nodeKind = _resolveNodeKind(node);
    final isBrowsable = nodeKind == 'table' || nodeKind == 'view';

    return material.InkWell(
      onTap: isBrowsable ? () => widget.onNodeSelected?.call(node) : null,
      child: material.Padding(
        padding: material.EdgeInsets.only(
          left: 8.0 + depth * 16.0,
          right: 8,
        ),
        child: material.Row(
          children: [
            if (canExpand)
              material.SizedBox(
                width: 28,
                height: 28,
                child: material.IconButton(
                  padding: material.EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: () {
                    if (isExpanded) {
                      _onCollapse(node);
                    } else {
                      _onExpand(node);
                    }
                  },
                  icon: material.Icon(
                    isExpanded
                        ? material.Icons.expand_more
                        : material.Icons.chevron_right,
                  ),
                ),
              )
            else
              const material.SizedBox(width: 28),
            if (isLoading)
              const material.SizedBox(
                width: 14,
                height: 14,
                child: material.CircularProgressIndicator(strokeWidth: 2),
              )
            else
              material.Icon(
                _iconFor(node),
                size: 16,
              ),
            const Gap(8),
            material.Expanded(
              child: material.Text(
                node.label,
                overflow: material.TextOverflow.ellipsis,
                maxLines: 1,
                style: material.TextStyle(
                  fontSize: 12,
                  fontWeight: isBrowsable ? material.FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resolveNodeKind(SduiTreeNode node) {
    final fromMeta =
        '${node.meta['nodeType'] ?? node.meta['node_type'] ?? ''}'.trim();
    if (fromMeta.isNotEmpty) return fromMeta;
    final parts = node.id.split('.');
    return parts.isNotEmpty ? parts.first : '';
  }

  material.IconData _iconFor(SduiTreeNode node) {
    switch (node.icon) {
      case 'database':
        return material.Icons.storage_outlined;
      case 'table':
        return material.Icons.table_chart_outlined;
      case 'view':
      case 'eye':
        return material.Icons.visibility_outlined;
      case 'folder':
      case 'folder-table':
        return material.Icons.folder_outlined;
      case 'folder-eye':
        return material.Icons.folder_special_outlined;
      case 'folder-book':
      case 'book':
        return material.Icons.menu_book_outlined;
      case 'columns':
        return material.Icons.view_column_outlined;
      case 'archive':
        return material.Icons.inventory_2_outlined;
      default:
        return node.expandable
            ? material.Icons.folder_outlined
            : material.Icons.insert_drive_file_outlined;
    }
  }
}
