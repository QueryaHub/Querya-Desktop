import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Name and note of a diagram group (#1282), as the user typed them.
typedef ErdGroupText = ({String name, String? note});

/// Asks for a group's name and an optional note. [title] is "New group" or
/// "Edit group"; null when cancelled.
Future<ErdGroupText?> showErdGroupDialog(
  BuildContext context, {
  required String title,
  required String action,
  String name = '',
  String? note,
}) {
  return showAppDialog<ErdGroupText>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _ErdGroupDialog(
          title: title, action: action, name: name, note: note ?? ''),
    ),
  );
}

class _ErdGroupDialog extends material.StatefulWidget {
  const _ErdGroupDialog({
    required this.title,
    required this.action,
    required this.name,
    required this.note,
  });

  final String title;
  final String action;
  final String name;
  final String note;

  @override
  material.State<_ErdGroupDialog> createState() => _ErdGroupDialogState();
}

class _ErdGroupDialogState extends material.State<_ErdGroupDialog> {
  late final _name = material.TextEditingController(text: widget.name);
  late final _note = material.TextEditingController(text: widget.note);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final note = _note.text.trim();
    material.Navigator.of(context)
        .pop<ErdGroupText>((name: name, note: note.isEmpty ? null : note));
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
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                Text(widget.title).large().semiBold(),
                const material.SizedBox(height: 6),
                const Text('A frame around the tables on the diagram. '
                        'Kept in Querya, not in the database.')
                    .muted()
                    .small(),
                const material.SizedBox(height: 16),
                TextField(
                  key: const material.ValueKey('erd_group_name'),
                  controller: _name,
                  autofocus: true,
                  placeholder: const Text('Group name'),
                  onSubmitted: (_) => _submit(),
                ),
                const material.SizedBox(height: 8),
                TextField(
                  key: const material.ValueKey('erd_group_note'),
                  controller: _note,
                  placeholder: const Text('Note (optional)'),
                  onSubmitted: (_) => _submit(),
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
                  listenable: _name,
                  builder: (context, _) => PrimaryButton(
                    key: const material.ValueKey('erd_group_submit'),
                    onPressed: _name.text.trim().isEmpty ? null : _submit,
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
