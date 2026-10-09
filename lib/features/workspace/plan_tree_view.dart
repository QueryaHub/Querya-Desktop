import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/workspace/query_plan.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// The plan as a tree, top-down. The node with the largest own cost is
/// highlighted; each node shows its share of the total cost as a bar. A click
/// on a node shows every field the driver reported for it.
class PlanTreeView extends material.StatefulWidget {
  const PlanTreeView({super.key, required this.root});

  final PlanNode root;

  @override
  material.State<PlanTreeView> createState() => _PlanTreeViewState();
}

class _PlanTreeViewState extends material.State<PlanTreeView> {
  PlanNode? _selected;

  @override
  material.Widget build(material.BuildContext context) {
    final root = widget.root;
    final hottest = QueryPlanParser.hottest(root);
    final total = root.cost ?? _sumOwn(root);
    final rows = <material.Widget>[];
    void add(PlanNode node, int depth) {
      rows.add(_PlanRow(
        node: node,
        depth: depth,
        hottest: identical(node, hottest),
        selected: identical(node, _selected),
        total: total,
        onTap: () => setState(() => _selected = identical(node, _selected) ? null : node),
      ));
      for (final child in node.children) {
        add(child, depth + 1);
      }
    }

    add(root, 0);
    final selected = _selected;
    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.all(8),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          ...rows,
          if (selected != null) _DetailsPanel(node: selected),
        ],
      ),
    );
  }

  static double _sumOwn(PlanNode n) {
    var sum = n.ownCost ?? 0;
    for (final c in n.children) {
      sum += _sumOwn(c);
    }
    return sum;
  }
}

class _PlanRow extends material.StatelessWidget {
  const _PlanRow({
    required this.node,
    required this.depth,
    required this.hottest,
    required this.selected,
    required this.total,
    required this.onTap,
  });

  final PlanNode node;
  final int depth;
  final bool hottest;
  final bool selected;
  final double total;
  final material.VoidCallback onTap;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final own = node.ownCost;
    final share = own == null || total <= 0 ? 0.0 : (own / total).clamp(0.0, 1.0);
    final rowsText = node.estimatedRows == null
        ? null
        : 'rows ${node.estimatedRows!.round()}'
            '${node.actualRows == null ? '' : ' → ${node.actualRows!.round()}'}';
    return material.Padding(
      padding: material.EdgeInsets.only(left: depth * 18.0, bottom: 6),
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onTap: onTap,
        child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: material.BoxDecoration(
          color: hottest ? wb.accent.withValues(alpha: 0.12) : null,
          border: material.Border.all(
            color: selected
                ? Theme.of(context).colorScheme.foreground
                : hottest
                    ? wb.accent
                    : wb.borderSubtle,
            width: hottest || selected ? 1.5 : 1,
          ),
          borderRadius: material.BorderRadius.circular(6),
        ),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Row(
              children: [
                material.Text(node.operation,
                    style: const material.TextStyle(fontWeight: material.FontWeight.w600)),
                if (node.relation != null) ...[
                  const material.SizedBox(width: 8),
                  material.Text(node.relation!,
                      style: material.TextStyle(color: wb.mutedForeground)),
                ],
              ],
            ),
            if (rowsText != null)
              material.Text(rowsText,
                  style: material.TextStyle(fontSize: 11, color: wb.mutedForeground)),
            if (own != null) ...[
              const material.SizedBox(height: 4),
              material.Stack(
                children: [
                  material.Container(height: 4, width: 160, color: wb.borderSubtle),
                  material.Container(height: 4, width: 160 * share, color: wb.accent),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// Every field the driver reported for a node, in the order it reported them.
class _DetailsPanel extends material.StatelessWidget {
  const _DetailsPanel({required this.node});

  final PlanNode node;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final fields = <String, String>{
      'Operation': node.operation,
      if (node.relation != null) 'Relation': node.relation!,
      if (node.estimatedRows != null)
        'Estimated rows': '${node.estimatedRows!.round()}',
      if (node.actualRows != null) 'Actual rows': '${node.actualRows!.round()}',
      if (node.cost != null) 'Cost': node.cost!.toStringAsFixed(2),
      if (node.ownCost != null) 'Own cost': node.ownCost!.toStringAsFixed(2),
      ...node.details,
    };
    return material.Container(
      margin: const material.EdgeInsets.only(top: 8),
      padding: const material.EdgeInsets.all(10),
      decoration: material.BoxDecoration(
        border: material.Border.all(color: wb.borderSubtle),
        borderRadius: material.BorderRadius.circular(6),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          for (final e in fields.entries)
            material.Padding(
              padding: const material.EdgeInsets.symmetric(vertical: 2),
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.SizedBox(
                    width: 140,
                    child: material.Text(e.key,
                        style: material.TextStyle(color: wb.mutedForeground)),
                  ),
                  material.Expanded(child: material.SelectableText(e.value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
