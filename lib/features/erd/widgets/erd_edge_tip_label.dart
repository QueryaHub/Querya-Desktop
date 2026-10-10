import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// "orders.customer_id → customers.id" next to the pointer.
class ErdEdgeTipLabel extends material.StatelessWidget {
  const ErdEdgeTipLabel({super.key, required this.relation});

  final ErdRelation relation;

  @override
  material.Widget build(material.BuildContext context) {
    final r = relation;
    final cs = Theme.of(context).colorScheme;
    return material.DecoratedBox(
      decoration: material.BoxDecoration(
        color: cs.popover,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(color: cs.border),
      ),
      child: material.Padding(
        padding:
            const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: material.Text(
          '${r.fromTable}.${r.fromColumn} → ${r.toTable}.${r.toColumn}',
          style:
              material.TextStyle(fontSize: 11, color: cs.popoverForeground),
        ),
      ),
    );
  }
}
