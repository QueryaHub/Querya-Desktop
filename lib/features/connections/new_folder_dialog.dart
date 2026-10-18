import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Shows a dialog to create a new folder (same style as new connection).
/// Returns the folder name or null if cancelled.
Future<String?> showNewFolderDialog(BuildContext context) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _NewFolderDialogContent(),
    ),
  );
}

class _NewFolderDialogContent extends material.StatefulWidget {
  const _NewFolderDialogContent();

  @override
  material.State<_NewFolderDialogContent> createState() =>
      _NewFolderDialogContentState();
}

class _NewFolderDialogContentState
    extends material.State<_NewFolderDialogContent> {
  final _nameController = material.TextEditingController();
  String get _name => _nameController.text.trim();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 440,
        minWidth: 360,
      ),
      borderColor: theme.muted,
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
                    border: material.Border.all(
                        color: theme.border.withValues(alpha: 0.4)),
                  ),
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: material.Row(
                    children: [
                      material.Icon(
                        material.Icons.folder_rounded,
                        size: 20,
                        color: theme.mutedForeground,
                      ),
                      const material.SizedBox(width: 10),
                      material.Expanded(
                        child: QueryaTextField(
                          controller: _nameController,
                          placeholder: 'Folder name',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _nameController,
            builder: (context, __) => QueryaDialogActions(
              cancel: QueryaButton.ghost(
                  label: 'Cancel',
                  onPressed: () => material.Navigator.of(context).pop(),
                  size: QueryaControlSize.lg,
                ),
              primary: QueryaButton.primary(
                    label: 'Create',
                    onPressed: _name.isEmpty
                        ? null
                        : () => material.Navigator.of(context).pop(_name),
                    size: QueryaControlSize.lg,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
