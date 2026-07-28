import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/core/ui/querya_tree_tokens.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders a sidebar-style tree from an SDUI schema with lazy expansion.
///
/// Visible rows are flattened into a [ListView.builder] so only viewport
/// rows are built (large schemas no longer create a full widget Column).
/// Expand chevrons and height morph share [QueryaMotion.treeExpand] /
/// [QueryaMotion.treeExpandCurve]. Height morph via [QueryaAnimatedExpand] is
/// not used on the flat virtualized row list (nested expand would fight
/// `ListView` itemExtent); chevron timing still matches native trees.
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
            padding: material.EdgeInsets.only(
              left: 36.0 + row.depth * QueryaTreeTokens.indent,
            ),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.mutedForeground;
    final canExpand = node.expandable || node.hasChildren;
    final isExpanded = _expanded.contains(node.id);
    final isLoading = _loading.contains(node.id);
    final nodeKind = _resolveNodeKind(node);
    final isBrowsable = nodeKind == 'table' || nodeKind == 'view';
    // Same hierarchy as native trees (#476 / #497) — no separate sduiNode size.
    final iconSize =
        canExpand ? QueryaIconSizes.treeGroup : QueryaIconSizes.treeLeaf;
    final iconColor = isBrowsable
        ? QueryaTreeTokens.leafIconColor(theme.colorScheme.primary)
        : muted;
    final rowLeft =
        8.0 + depth * QueryaTreeTokens.indent + (canExpand ? 0 : 4.0);

    return material.InkWell(
      onTap: () {
        if (isBrowsable) {
          widget.onNodeSelected?.call(node);
        } else if (canExpand) {
          _toggleExpand(node);
        }
      },
      borderRadius: material.BorderRadius.circular(4),
      child: material.Padding(
        padding: material.EdgeInsets.only(
          left: rowLeft,
          right: 8,
        ),
        child: material.Row(
          children: [
            if (canExpand)
              material.MouseRegion(
                cursor: material.SystemMouseCursors.click,
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.opaque,
                  onTap: () => _toggleExpand(node),
                  child: material.Padding(
                    padding: const material.EdgeInsets.all(2),
                    child: material.AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: context.motionDuration(QueryaMotion.treeExpand),
                      curve: context.motionCurve(QueryaMotion.treeExpandCurve),
                      child: material.Icon(
                        QueryaIcons.expandClosed,
                        size: QueryaIconSizes.treeExpand,
                        color: muted,
                      ),
                    ),
                  ),
                ),
              )
            else
              const material.SizedBox(width: QueryaIconSizes.treeExpand + 4),
            if (isLoading)
              const material.SizedBox(
                width: 14,
                height: 14,
                child: material.CircularProgressIndicator(strokeWidth: 2),
              )
            else
              material.Icon(
                QueryaIcons.sduiNodeIcon(
                  node.icon,
                  expandable: node.expandable,
                ),
                size: iconSize,
                color: iconColor,
              ),
            const Gap(8),
            material.Expanded(
              child: material.Text(
                node.label,
                overflow: material.TextOverflow.ellipsis,
                maxLines: 1,
                style: material.TextStyle(
                  fontSize: 11,
                  color: isBrowsable ? theme.colorScheme.foreground : muted,
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
}
