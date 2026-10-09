import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/workspace/query_plan.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// The plan as a tree, top-down. The node with the largest own cost is
/// highlighted; each node shows its share of the total cost as a bar.
class PlanTreeView extends material.StatelessWidget {
  const PlanTreeView({super.key, required this.root});

  final PlanNode root;

  @override
  material.Widget build(material.BuildContext context) {
    final hottest = QueryPlanParser.hottest(root);
    final total = root.cost ?? _sumOwn(root);
    final rows = <material.Widget>[];
    void add(PlanNode node, int depth) {
      rows.add(_PlanRow(
        node: node,
        depth: depth,
        hottest: identical(node, hottest),
        total: total,
      ));
      for (final child in node.children) {
        add(child, depth + 1);
      }
    }

    add(root, 0);
    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.all(8),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: rows,
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
    required this.total,
  });

  final PlanNode node;
  final int depth;
  final bool hottest;
  final double total;

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
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: material.BoxDecoration(
          color: hottest ? wb.accent.withValues(alpha: 0.12) : null,
          border: material.Border.all(
            color: hottest ? wb.accent : wb.borderSubtle,
            width: hottest ? 1.5 : 1,
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
    );
  }
}
