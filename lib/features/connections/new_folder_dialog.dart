import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows a dialog to create a new folder (same style as new connection).
/// Returns the folder name or null if cancelled.
Future<String?> showNewFolderDialog(BuildContext context) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => const material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: _NewFolderDialogContent(),
    ),
  );
}

class _NewFolderDialogContent extends material.StatefulWidget {
  const _NewFolderDialogContent();

  @override
  material.State<_NewFolderDialogContent> createState() => _NewFolderDialogContentState();
}

class _NewFolderDialogContentState extends material.State<_NewFolderDialogContent> {
  final _nameController = material.TextEditingController();
  String get _name => _nameController.text.trim();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 440, minWidth: 360),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('New folder').large().semiBold(),
                  const material.SizedBox(height: 6),
                  const Text(
                    'Enter a name for the new folder in the browser tree.',
                  ).muted().small(),
                  const material.SizedBox(height: 16),
                  material.Container(
                    decoration: material.BoxDecoration(
                      color: theme.muted.withValues(alpha: 0.2),
                      borderRadius: material.BorderRadius.circular(8),
                      border: material.Border.all(color: theme.border.withValues(alpha: 0.4)),
                    ),
                    padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: material.Row(
                      children: [
                        material.Icon(
                          material.Icons.folder_rounded,
                          size: 20,
                          color: theme.mutedForeground,
                        ),
                        const material.SizedBox(width: 10),
                        material.Expanded(
                          child: TextField(
                            controller: _nameController,
                            placeholder: const Text('Folder name'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: material.BoxDecoration(
                border: material.Border(
                  top: material.BorderSide(color: theme.border.withValues(alpha: 0.3)),
                ),
              ),
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  GhostButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const material.SizedBox(width: 12),
                  PrimaryButton(
                    onPressed: _name.isEmpty
                        ? null
                        : () => material.Navigator.of(context).pop(_name),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
