import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/unsaved_work_registry.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Confirms before Home / Close / tree navigation discards SQL or staged grid
/// edits. Returns true when it is safe to tear down the current view.
Future<bool> confirmDiscardUnsavedWorkIfNeeded(
  material.BuildContext context,
) async {
  if (!UnsavedWorkRegistry.instance.hasUnsaved) return true;
  final confirmed = await showDiscardUnsavedWorkDialog(context);
  return confirmed == true;
}

/// Prompt when leaving a workspace that has unsaved SQL or table edits.
Future<bool?> showDiscardUnsavedWorkDialog(material.BuildContext context) {
  return showAppDialog<bool>(
    context: context,
    builder: (ctx) {
      return QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 420),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              const Text('Unsaved changes').semiBold().large(),
              const Gap(8),
              const Text(
                'You have unsaved SQL or staged table edits. '
                'Continuing will discard them.',
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
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
