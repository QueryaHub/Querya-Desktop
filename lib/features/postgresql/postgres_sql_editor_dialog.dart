import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Returns true if [sql] is allowed to run (read-only: SELECT / WITH).
bool isAllowedPostgresSelectQuery(String sql) {
  final t = sql.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  const blocked = [
    'insert ',
    'update ',
    'delete ',
    'drop ',
    'truncate ',
    'alter ',
    'create ',
    'grant ',
    'revoke ',
    'call ',
    'execute ',
    'copy ',
  ];
  for (final b in blocked) {
    if (lower.contains(b)) return false;
  }
  return lower.startsWith('select') ||
      lower.startsWith('with') ||
      lower.startsWith('(');
}

/// Dialog to view/edit SQL and run it.
/// [initialSql] — text shown when opening; [browseSql] — "Reset" restores table browse query.
Future<void> showPostgresSqlEditorDialog({
  required material.BuildContext context,
  required String initialSql,
  required String browseSql,
  required void Function(String sql) onRun,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: material.Colors.black54,
    builder: (ctx) => _PostgresSqlEditorDialog(
      initialSql: initialSql,
      browseSql: browseSql,
      onRun: onRun,
    ),
  );
}

class _PostgresSqlEditorDialog extends material.StatefulWidget {
  const _PostgresSqlEditorDialog({
    required this.initialSql,
    required this.browseSql,
    required this.onRun,
  });

  final String initialSql;
  final String browseSql;
  final void Function(String sql) onRun;

  @override
  material.State<_PostgresSqlEditorDialog> createState() =>
      _PostgresSqlEditorDialogState();
}

class _PostgresSqlEditorDialogState extends material.State<_PostgresSqlEditorDialog> {
  late final material.TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.initialSql);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final sql = _controller.text.trim();
    if (sql.isEmpty) {
      setState(() => _error = 'Enter a SQL query');
      return;
    }
    if (!isAllowedPostgresSelectQuery(sql)) {
      setState(() =>
          _error = 'Only SELECT queries (and WITH … SELECT) are allowed.');
      return;
    }
    material.Navigator.of(context).pop();
    widget.onRun(sql);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding:
          const material.EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: material.Container(
        constraints: const material.BoxConstraints(
          maxWidth: 720,
          minWidth: 480,
          maxHeight: 520,
        ),
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
                padding: const material.EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    const Text('SQL query').large().semiBold(),
                    const material.SizedBox(height: 6),
                    const Text(
                      'Table browse uses SELECT with LIMIT/OFFSET. '
                      'Edit it or write your own SELECT. Reset restores the table browse query.',
                    ).muted().xSmall(),
                  ],
                ),
              ),
              material.Padding(
                padding: const material.EdgeInsets.symmetric(horizontal: 24),
                child: material.SizedBox(
                  height: 280,
                  child: material.Container(
                    decoration: material.BoxDecoration(
                      color: theme.muted.withValues(alpha: 0.15),
                      borderRadius: material.BorderRadius.circular(8),
                      border: material.Border.all(
                          color: theme.border.withValues(alpha: 0.4)),
                    ),
                    child: material.TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: material.TextAlignVertical.top,
                      style: material.TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.foreground,
                      ),
                      decoration: const material.InputDecoration(
                        border: material.InputBorder.none,
                        contentPadding: material.EdgeInsets.all(12),
                        hintText: 'SELECT …',
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null)
                material.Padding(
                  padding:
                      const material.EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: material.Text(
                    _error!,
                    style: material.TextStyle(
                        color: theme.destructive, fontSize: 12),
                  ),
                ),
              material.Padding(
                padding: const material.EdgeInsets.all(20),
                child: material.Row(
                  mainAxisAlignment: material.MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      onPressed: () =>
                          material.Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Gap(8),
                    OutlineButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _controller.text = widget.browseSql;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                    const Gap(8),
                    PrimaryButton(
                      onPressed: _submit,
                      child: const Text('Run'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
