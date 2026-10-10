import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Asks before a folder with connections is removed: removing it deletes them
/// and their saved passwords. Returns true to remove.
Future<bool> confirmRemoveFolder(
  material.BuildContext context, {
  required String name,
  required int connectionCount,
}) async {
  final noun = connectionCount == 1 ? 'connection' : 'connections';
  final result = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => QueryaDialogCard(
      constraints: const material.BoxConstraints(maxWidth: 440),
      child: material.Padding(
        padding: const material.EdgeInsets.all(20),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            Text('Remove folder "$name"?').semiBold().large(),
            const Gap(8),
            Text(
              'The folder holds $connectionCount $noun. Removing it deletes '
              '${connectionCount == 1 ? 'it' : 'them'} and the saved '
              '${connectionCount == 1 ? 'password' : 'passwords'}. This cannot '
              'be undone.',
            ).muted().small(),
            const Gap(20),
            material.Align(
              alignment: material.Alignment.centerRight,
              child: material.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlineButton(
                    onPressed: () => material.Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  DestructiveButton(
                    onPressed: () => material.Navigator.of(ctx).pop(true),
                    child: const Text('Remove folder'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
