import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders a sidebar-style tree from an SDUI schema with lazy expansion.
class SduiTreeBuilder extends material.StatefulWidget {
  const SduiTreeBuilder({
    super.key,
    required this.schema,
    this.fetchChildren,
    this.onNodeSelected,
  });

  final SduiTreeSchema schema;
  final SduiFetchTreeChildren? fetchChildren;
  final void Function(SduiTreeNode node)? onNodeSelected;

  @override
  material.State<SduiTreeBuilder> createState() => SduiTreeBuilderState();
}

class SduiTreeBuilderState extends material.State<SduiTreeBuilder> {
  late List<SduiTreeNode> _roots;
  final Set<String> _loading = {};
  final Set<String> _loaded = {};
  final Set<String> _expanded = {};

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
    }
  }

  Future<void> _onExpand(SduiTreeNode node) async {
    setState(() => _expanded.add(node.id));
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
        _roots = _replaceNode(_roots, node.id, (n) => n.copyWith(children: children));
        _loaded.add(node.id);
        _loading.remove(node.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading.remove(node.id));
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

  @override
  material.Widget build(material.BuildContext context) {
    return material.ListView(
      shrinkWrap: true,
      children: [
        for (final root in _roots) _buildNode(root, depth: 0),
      ],
    );
  }

  material.Widget _buildNode(SduiTreeNode node, {required int depth}) {
    final canExpand = node.expandable || node.hasChildren;
    final isExpanded = _expanded.contains(node.id);
    final isLoading = _loading.contains(node.id);

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.InkWell(
          onTap: () => widget.onNodeSelected?.call(node),
          child: material.Padding(
            padding: material.EdgeInsets.only(
              left: 8.0 + depth * 16.0,
              right: 8,
              top: 6,
              bottom: 6,
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
                material.Expanded(child: Text(node.label).small()),
              ],
            ),
          ),
        ),
        if (isExpanded)
          for (final child in node.children) _buildNode(child, depth: depth + 1),
      ],
    );
  }

  material.IconData _iconFor(SduiTreeNode node) {
    switch (node.icon) {
      case 'database':
        return material.Icons.storage_outlined;
      case 'table':
        return material.Icons.table_chart_outlined;
      case 'folder':
        return material.Icons.folder_outlined;
      default:
        return node.expandable
            ? material.Icons.folder_outlined
            : material.Icons.insert_drive_file_outlined;
    }
  }
}
