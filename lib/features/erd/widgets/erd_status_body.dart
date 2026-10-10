import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_empty_state.dart';

/// What the diagram area shows instead of the canvas.
abstract final class ErdStatusBody {
  static material.Widget error(
    material.BuildContext context, {
    required String? message,
    required material.VoidCallback onRetry,
  }) {
    final wb = context.workbench;
    return material.Center(
      child: QueryaEmptyState(
        icon: material.Icon(material.Icons.error_outline_rounded,
            color: wb.destructive),
        title: 'Could not load the schema',
        description: message,
        actionLabel: 'Retry',
        onAction: onRetry,
      ),
    );
  }

  /// Every table was hidden from the diagram: they exist, so say so and offer
  /// them back instead of "No tables found".
  static material.Widget allHidden(
    material.BuildContext context, {
    required int hiddenCount,
    required material.VoidCallback onShowAll,
  }) {
    final wb = context.workbench;
    return material.Center(
      child: QueryaEmptyState(
        icon: material.Icon(material.Icons.visibility_off_outlined,
            color: wb.mutedForeground),
        title: 'All tables are hidden',
        description: '$hiddenCount '
            '${hiddenCount == 1 ? 'table is' : 'tables are'} hidden '
            'from the diagram.',
        actionLabel: 'Show all tables',
        onAction: onShowAll,
      ),
    );
  }

  static material.Widget noTables(
    material.BuildContext context, {
    required String databaseName,
  }) {
    final wb = context.workbench;
    final db = databaseName;
    return material.Center(
      child: QueryaEmptyState(
        icon: material.Icon(material.Icons.table_chart_outlined,
            color: wb.mutedForeground),
        title: 'No tables found',
        description: db.isEmpty
            ? 'This schema has no tables, or this role cannot see them.'
            : 'The current schema of $db has no tables, or this role '
                'cannot see them.',
      ),
    );
  }

  static material.Widget noRelations(
    material.BuildContext context, {
    required String? focusTable,
    required material.VoidCallback? onOpenFullDiagram,
  }) {
    final wb = context.workbench;
    return material.Center(
      child: QueryaEmptyState(
        icon: material.Icon(material.Icons.link_off_rounded,
            color: wb.mutedForeground),
        title: 'No foreign keys to or from $focusTable',
        description: 'This table has no relations within the schema.',
        actionLabel: 'Open full diagram',
        onAction: onOpenFullDiagram,
      ),
    );
  }
}
