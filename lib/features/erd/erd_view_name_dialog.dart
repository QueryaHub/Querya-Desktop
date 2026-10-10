import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Asks for the name of a saved diagram view (#1284); null when cancelled.
Future<String?> showErdViewNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String name = '',
}) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: _ErdViewNameDialog(title: title, action: action, name: name),
    ),
  );
}

class _ErdViewNameDialog extends material.StatefulWidget {
  const _ErdViewNameDialog({
    required this.title,
    required this.action,
    required this.name,
  });

  final String title;
  final String action;
  final String name;

  @override
  material.State<_ErdViewNameDialog> createState() =>
      _ErdViewNameDialogState();
}

class _ErdViewNameDialogState extends material.State<_ErdViewNameDialog> {
  late final _name = material.TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    material.Navigator.of(context).pop(name);
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
                const Text('A view keeps the tables shown, their positions, '
                        'groups, notes and the viewport. Kept in Querya.')
                    .muted()
                    .small(),
                const material.SizedBox(height: 16),
                TextField(
                  key: const material.ValueKey('erd_view_name'),
                  controller: _name,
                  autofocus: true,
                  placeholder: const Text('View name'),
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
                    key: const material.ValueKey('erd_view_submit'),
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
