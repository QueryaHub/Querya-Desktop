import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_metadata.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows [information_schema.role_table_grants] for a table/view/matview.
Future<void> showPostgresTablePrivilegesDialog({
  required material.BuildContext context,
  required PostgresConnection connection,
  required String schema,
  required String tableName,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _PrivilegesDialogBody(
      connection: connection,
      schema: schema,
      tableName: tableName,
    ),
  );
}

class _PrivilegesDialogBody extends material.StatefulWidget {
  const _PrivilegesDialogBody({
    required this.connection,
    required this.schema,
    required this.tableName,
  });

  final PostgresConnection connection;
  final String schema;
  final String tableName;

  @override
  material.State<_PrivilegesDialogBody> createState() =>
      _PrivilegesDialogBodyState();
}

class _PrivilegesDialogBodyState extends material.State<_PrivilegesDialogBody> {
  bool _loading = true;
  String? _error;
  List<PgTablePrivilegeRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.connection.listTablePrivileges(
        widget.schema,
        widget.tableName,
      );
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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
          maxWidth: 560,
          maxHeight: 480,
        ),
        decoration: material.BoxDecoration(
          color: theme.popover,
          borderRadius: material.BorderRadius.circular(radius),
          border: material.Border.all(color: theme.muted),
        ),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Table privileges').large().semiBold(),
                  const material.SizedBox(height: 4),
                  Text(
                    '${widget.schema}.${widget.tableName}',
                    style: material.TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.mutedForeground,
                    ),
                  ),
                  const material.SizedBox(height: 4),
                  const Text(
                    'From information_schema.role_table_grants (read-only).',
                  ).muted().xSmall(),
                ],
              ),
            ),
            const material.Divider(height: 1),
            material.SizedBox(
              height: 300,
              child: _loading
                  ? const material.Center(
                      child: material.CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                      ? material.Center(
                          child: material.Padding(
                            padding: const material.EdgeInsets.all(16),
                            child: material.SelectableText(
                              _error!,
                              style: material.TextStyle(color: theme.destructive),
                            ),
                          ),
                        )
                      : material.ListView(
                          padding: const material.EdgeInsets.all(12),
                          children: [
                            for (final r in _rows)
                              material.Padding(
                                padding:
                                    const material.EdgeInsets.only(bottom: 8),
                                child: material.Row(
                                  crossAxisAlignment:
                                      material.CrossAxisAlignment.start,
                                  children: [
                                    material.SizedBox(
                                      width: 140,
                                      child: material.Text(
                                        r.grantee,
                                        style: material.TextStyle(
                                          fontSize: 12,
                                          color: theme.foreground,
                                        ),
                                      ),
                                    ),
                                    material.Expanded(
                                      child: material.Text(
                                        r.privilegeType,
                                        style: material.TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: theme.foreground,
                                        ),
                                      ),
                                    ),
                                    Text(r.isGrantable).xSmall().muted(),
                                  ],
                                ),
                              ),
                            if (_rows.isEmpty)
                              const Text(
                                'No grants found (or no permission to view).',
                              ).muted().small(),
                          ],
                        ),
            ),
            material.Padding(
              padding: const material.EdgeInsets.all(12),
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  OutlineButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  if (!_loading && _error == null) ...[
                    const Gap(8),
                    OutlineButton(
                      onPressed: _load,
                      child: const Text('Reload'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
