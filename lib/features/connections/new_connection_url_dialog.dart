import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_url_parser.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows a dialog to create a new database connection from a URI.
/// Returns the ConnectionRow or null if cancelled.
Future<ConnectionRow?> showNewConnectionUrlDialog(
    material.BuildContext context) {
  return showAppDialog<ConnectionRow>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _NewConnectionUrlDialogContent(),
    ),
  );
}

class _NewConnectionUrlDialogContent extends material.StatefulWidget {
  const _NewConnectionUrlDialogContent();

  @override
  material.State<_NewConnectionUrlDialogContent> createState() =>
      _NewConnectionUrlDialogContentState();
}

class _NewConnectionUrlDialogContentState
    extends material.State<_NewConnectionUrlDialogContent> {
  final _urlController = material.TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final result = parseConnectionUrlInput(_urlController.text);
    if (result.error != null) {
      setState(() => _validationError = result.error);
      return;
    }
    material.Navigator.of(context).pop(result.row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 580,
        minWidth: 420,
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
                const Text('New connection from URL').large().semiBold(),
                const material.SizedBox(height: 6),
                const Text(
                  'Create a connection by pasting a database URI (e.g. postgresql://user:pass@host:5432/db).',
                ).muted().small(),
                const material.SizedBox(height: 16),
                material.Container(
                  decoration: material.BoxDecoration(
                    color: theme.muted.withValues(alpha: 0.2),
                    borderRadius: material.BorderRadius.circular(8),
                    border: material.Border.all(
                      color: _validationError != null
                          ? theme.destructive.withValues(alpha: 0.8)
                          : theme.border.withValues(alpha: 0.4),
                    ),
                  ),
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: material.Row(
                    children: [
                      material.Icon(
                        material.Icons.link_rounded,
                        size: 20,
                        color: _validationError != null
                            ? theme.destructive
                            : theme.mutedForeground,
                      ),
                      const material.SizedBox(width: 10),
                      material.Expanded(
                        child: TextField(
                          controller: _urlController,
                          placeholder:
                              const Text('database://user:pass@host:port/db'),
                          onSubmitted: (_) => _validateAndSubmit(),
                          onChanged: (_) {
                            if (_validationError != null) {
                              setState(() => _validationError = null);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_validationError != null) ...[
                  const material.SizedBox(height: 8),
                  Text(
                    _validationError!,
                    style: material.TextStyle(color: theme.destructive),
                  ).small(),
                ],
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
                PrimaryButton(
                  onPressed: _validateAndSubmit,
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
