import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';
import 'package:querya_desktop/features/connections/querya_connection_tree_row.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders a sidebar-style tree from an SDUI schema with lazy expansion.
///
/// Visible rows are flattened into a [ListView.builder] so only viewport
/// rows are built (large schemas no longer create a full widget Column).
/// Row chrome matches native [QueryaConnectionTreeRow] (selection, gaps,
/// bold-when-selected, keyboard expand, context menu).
class SduiTreeBuilder extends material.StatefulWidget {
  const SduiTreeBuilder({
    super.key,
    required this.schema,
    this.fetchChildren,
    this.onNodeSelected,
    this.selectedNodeId,
    this.isNodeSelected,
    this.maxHeight,
    this.connection,
  });

  final SduiTreeSchema schema;
  final SduiFetchTreeChildren? fetchChildren;
  final void Function(SduiTreeNode node)? onNodeSelected;
  final String? selectedNodeId;
  final bool Function(SduiTreeNode node)? isNodeSelected;

  /// When set, the tree scrolls inside a height cap (sidebar use).
  final double? maxHeight;

  /// Optional connection for tree context menus (Refresh / Copy name).
  final ConnectionRow? connection;

  @override
  material.State<SduiTreeBuilder> createState() => SduiTreeBuilderState();
}

class _VisibleRow {
  const _VisibleRow.node(this.node, this.depth)
      : error = null,
        parent = null,
        isError = false;

  const _VisibleRow.error(this.error, this.depth, this.parent)
      : node = null,
        isError = true;

  final SduiTreeNode? node;
  final SduiTreeNode? parent;
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

  static const double _rowExtent = 28;

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

  void _toggleExpand(SduiTreeNode node) {
    if (_expanded.contains(node.id)) {
      _onCollapse(node);
    } else {
      _onExpand(node);
    }
  }

  Future<void> _retryExpand(SduiTreeNode node) async {
    setState(() {
      _expandErrors.remove(node.id);
      _loaded.remove(node.id);
      _roots = _replaceNode(
        _roots,
        node.id,
        (n) => n.copyWith(children: const []),
      );
    });
    await _onExpand(node);
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
        out.add(_VisibleRow.error(err, depth, node));
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
      itemExtent: rows.any((r) => r.isError) ? null : _rowExtent,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isError) {
          final parent = row.parent!;
          return TreeLoadError(
            title: 'Could not expand',
            message: row.error!,
            padding: QueryaTreeTokens.errorPaddingForDepth(row.depth),
            onRetry: () => _retryExpand(parent),
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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.mutedForeground;
    final canExpand = node.expandable || node.hasChildren;
    final isExpanded = _expanded.contains(node.id);
    final isLoading = _loading.contains(node.id);
    final nodeKind = _resolveNodeKind(node);
    final isBrowsable = nodeKind == 'table' || nodeKind == 'view';
    final isSelected = (widget.selectedNodeId != null &&
            node.id == widget.selectedNodeId) ||
        (widget.isNodeSelected != null && widget.isNodeSelected!(node));

    final iconSize =
        canExpand ? QueryaIconSizes.treeGroup : QueryaIconSizes.treeLeaf;
    final iconColor = isSelected
        ? primary
        : (isBrowsable
            ? QueryaTreeTokens.leafIconColor(primary)
            : muted);
    final rowLeft =
        8.0 + depth * QueryaTreeTokens.indent + (canExpand ? 0 : 4.0);

    final leading = canExpand
        ? material.AnimatedRotation(
            turns: isExpanded ? 0.25 : 0,
            duration: context.motionDuration(QueryaMotion.treeExpand),
            curve: context.motionCurve(QueryaMotion.treeExpandCurve),
            child: material.Icon(
              QueryaIcons.expandClosed,
              size: QueryaIconSizes.treeExpand,
              color: muted,
            ),
          )
        : const material.SizedBox(width: QueryaIconSizes.treeExpand);

    return material.Padding(
      padding: material.EdgeInsets.only(left: rowLeft),
      child: QueryaConnectionTreeRow(
        label: node.label,
        isSelected: isSelected,
        leading: leading,
        icon: isLoading
            ? null
            : QueryaIcons.sduiNodeIcon(
                node.icon,
                expandable: node.expandable,
              ),
        iconWidget: isLoading
            ? const material.SizedBox(
                width: QueryaTreeTokens.spinnerNested,
                height: QueryaTreeTokens.spinnerNested,
                child: material.CircularProgressIndicator(
                  strokeWidth: QueryaTreeTokens.spinnerStroke,
                ),
              )
            : null,
        iconSize: iconSize,
        iconColor: iconColor,
        textStyle: material.TextStyle(
          fontSize: 11,
          color: isBrowsable ? theme.colorScheme.foreground : muted,
        ),
        verticalPadding: 3,
        expanded: canExpand ? isExpanded : null,
        onTap: () {
          if (isBrowsable) {
            widget.onNodeSelected?.call(node);
          } else if (canExpand) {
            _toggleExpand(node);
          }
        },
        connection: widget.connection,
        onContextRefresh: canExpand ? () => _retryExpand(node) : null,
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
}
