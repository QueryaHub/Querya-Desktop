import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Asks for the text of a sticky note (#1283); null when cancelled.
Future<String?> showErdNoteDialog(
  BuildContext context, {
  required String title,
  required String action,
  String text = '',
}) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _ErdNoteDialog(title: title, action: action, text: text),
    ),
  );
}

class _ErdNoteDialog extends material.StatefulWidget {
  const _ErdNoteDialog({
    required this.title,
    required this.action,
    required this.text,
  });

  final String title;
  final String action;
  final String text;

  @override
  material.State<_ErdNoteDialog> createState() => _ErdNoteDialogState();
}

class _ErdNoteDialogState extends material.State<_ErdNoteDialog> {
  late final _text = material.TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 480,
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
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                Text(widget.title).large().semiBold(),
                const material.SizedBox(height: 6),
                const Text('**bold** and lines starting with "- " work. '
                        'Kept in Querya, not in the database.')
                    .muted()
                    .small(),
                const material.SizedBox(height: 16),
                TextField(
                  key: const material.ValueKey('erd_note_text'),
                  controller: _text,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  placeholder: const Text('Note'),
                ),
              ],
            ),
          ),
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 24, vertical: 16),
            decoration: material.BoxDecoration(
              border: material.Border(
                top: material.BorderSide(
                    color: theme.border.withValues(alpha: 0.3)),
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
                ListenableBuilder(
                  listenable: _text,
                  builder: (context, _) => PrimaryButton(
                    key: const material.ValueKey('erd_note_submit'),
                    onPressed: _text.text.trim().isEmpty
                        ? null
                        : () => material.Navigator.of(context)
                            .pop(_text.text.trim()),
                    child: Text(widget.action),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
