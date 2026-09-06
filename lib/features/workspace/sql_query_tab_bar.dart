import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/workspace/sql_query_tab_session.dart';
import 'package:querya_desktop/shared/widgets/app_dialog.dart';
import 'package:querya_desktop/shared/widgets/querya_tab_strip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lightweight query tab strip rendered above the SQL editor workspace.
class SqlQueryTabBar extends material.StatelessWidget {
  const SqlQueryTabBar({
    super.key,
    required this.sessions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    this.onClose,
  });

  final List<SqlQueryTabSession> sessions;
  final int selectedIndex;
  final material.ValueChanged<int> onSelect;
  final material.VoidCallback onAdd;
  final material.ValueChanged<int>? onClose;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return material.Container(
      height: 40,
      padding: const material.EdgeInsets.symmetric(horizontal: 8),
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border(
          bottom: material.BorderSide(color: cs.border),
        ),
      ),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.SingleChildScrollView(
              scrollDirection: material.Axis.horizontal,
              child: QueryaTabStrip(
                labels: sessions.map((s) => s.title).toList(),
                selectedIndex: selectedIndex,
                onSelected: onSelect,
                onClose: onClose,
                onAdd: onAdd,
                canClose: sessions.length > 1 ? (_) => true : (_) => false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts confirmation when attempting to close a query tab that has uncommitted
/// staged database modifications.
Future<bool?> showUnsavedTabChangesDialog({
  required material.BuildContext context,
  required String tabTitle,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;

      return material.Dialog(
        backgroundColor: cs.card,
        shape: material.RoundedRectangleBorder(
          borderRadius: material.BorderRadius.circular(8),
          side: material.BorderSide(color: cs.border, width: 1),
        ),
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(maxWidth: 420),
          child: material.Padding(
            padding: const material.EdgeInsets.all(20),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                Text('Unsaved Changes in "$tabTitle"').semiBold().large(),
                const Gap(8),
                const Text(
                  'This query tab contains staged database changes that have not been applied yet. Closing the tab will discard these changes.',
                ).muted().small(),
                const Gap(20),
                material.Align(
                  alignment: material.Alignment.centerRight,
                  child: material.Wrap(
                    alignment: material.WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlineButton(
                        onPressed: () => material.Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      DestructiveButton(
                        onPressed: () => material.Navigator.of(ctx).pop(true),
                        child: const Text('Discard & Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
