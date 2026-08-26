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
  ConnectionRow? _parsedRow;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final text = _urlController.text;
    if (text.trim().isEmpty) {
      setState(() {
        _parsedRow = null;
        _validationError = _touched ? 'URL/URI is required.' : null;
      });
      return;
    }
    _touched = true;
    final result = parseConnectionUrlInput(text);
    setState(() {
      _parsedRow = result.row;
      _validationError = result.error;
    });
  }

  void _validateAndSubmit() {
    _touched = true;
    final result = parseConnectionUrlInput(_urlController.text);
    if (result.error != null) {
      setState(() {
        _parsedRow = null;
        _validationError = result.error;
      });
      return;
    }
    material.Navigator.of(context).pop(result.row);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = context.colors;
    final isSuccess = _parsedRow != null;
    final isError = _validationError != null;

    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 580,
        minWidth: 420,
      ),
      borderColor: theme.muted,
      child: material.FocusTraversalGroup(
        policy: material.WidgetOrderTraversalPolicy(),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.FocusTraversalGroup(
              policy: material.WidgetOrderTraversalPolicy(),
              child: material.Padding(
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
                          color: isError
                              ? theme.destructive.withValues(alpha: 0.8)
                              : isSuccess
                                  ? theme.primary.withValues(alpha: 0.8)
                                  : theme.border.withValues(alpha: 0.4),
                        ),
                      ),
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: material.Row(
                        children: [
                          material.Icon(
                            isSuccess
                                ? material.Icons.check_circle_outline_rounded
                                : isError
                                    ? material.Icons.error_outline_rounded
                                    : material.Icons.link_rounded,
                            size: 20,
                            color: isError
                                ? theme.destructive
                                : isSuccess
                                    ? theme.primary
                                    : theme.mutedForeground,
                          ),
                          const material.SizedBox(width: 10),
                          material.Expanded(
                            child: TextField(
                              controller: _urlController,
                              placeholder:
                                  const Text('database://user:pass@host:port/db'),
                              onSubmitted: (_) => _validateAndSubmit(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isError) ...[
                      const material.SizedBox(height: 8),
                      Text(
                        _validationError!,
                        style: material.TextStyle(color: theme.destructive),
                      ).small(),
                    ] else if (isSuccess) ...[
                      material.Container(
                        margin: const material.EdgeInsets.only(top: 10),
                        padding: const material.EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: material.BoxDecoration(
                          color: theme.primary.withValues(alpha: 0.1),
                          borderRadius: material.BorderRadius.circular(6),
                          border: material.Border.all(
                            color: theme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: material.Row(
                          children: [
                            material.Icon(
                              material.Icons.task_alt_rounded,
                              size: 16,
                              color: theme.primary,
                            ),
                            const material.SizedBox(width: 8),
                            material.Expanded(
                              child: Text(
                                '${_parsedRow!.type.toUpperCase()} • ${_parsedRow!.name}',
                                style: material.TextStyle(
                                  fontSize: 12,
                                  fontWeight: material.FontWeight.w500,
                                  color: theme.primary,
                                ),
                                overflow: material.TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            material.FocusTraversalGroup(
              policy: material.WidgetOrderTraversalPolicy(),
              child: material.Container(
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
            ),
          ],
        ),
      ),
    );
  }
}
