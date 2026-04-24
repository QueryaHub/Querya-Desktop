import 'dart:math' as math;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
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
    final mq = material.MediaQuery.sizeOf(context);
    final dialogHeight =
        math.min(480.0, math.max(260.0, mq.height * 0.72)).toDouble();
    final dialogWidth =
        math.min(560.0, math.max(300.0, mq.width - 48)).toDouble();

    return material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: material.SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: material.DecoratedBox(
          decoration: material.BoxDecoration(
            color: theme.popover,
            borderRadius: material.BorderRadius.circular(radius),
            border: material.Border.all(color: theme.muted),
          ),
          child: material.ClipRRect(
            borderRadius: material.BorderRadius.circular(radius),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                material.Padding(
                  padding: const material.EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      const Text('Table privileges').large().semiBold(),
                      const material.SizedBox(height: 4),
                      material.Text(
                        '${widget.schema}.${widget.tableName}',
                        style: material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: theme.mutedForeground,
                        ),
                        maxLines: 2,
                        overflow: material.TextOverflow.ellipsis,
                      ),
                      const material.SizedBox(height: 4),
                      const Text(
                        'From information_schema.role_table_grants (read-only).',
                      ).muted().xSmall(),
                    ],
                  ),
                ),
                const material.Divider(height: 1),
                material.Expanded(child: _buildListArea(theme)),
                const material.Divider(height: 1),
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
        ),
      ),
    );
  }

  material.Widget _buildListArea(ColorScheme theme) {
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return material.Center(
        child: material.SingleChildScrollView(
          padding: const material.EdgeInsets.all(16),
          child: material.SelectableText(
            _error!,
            style: material.TextStyle(color: theme.destructive, fontSize: 13),
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return material.Center(
        child: const Text(
          'No grants found (or no permission to view).',
        ).muted().small(),
      );
    }
    return material.ListView.builder(
      padding: const material.EdgeInsets.all(12),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final r = _rows[i];
        return material.Padding(
          padding: const material.EdgeInsets.only(bottom: 8),
          child: material.Row(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              material.SizedBox(
                width: 132,
                child: material.Text(
                  r.grantee,
                  style: material.TextStyle(
                    fontSize: 12,
                    color: theme.foreground,
                  ),
                  maxLines: 3,
                  overflow: material.TextOverflow.ellipsis,
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
                  maxLines: 2,
                  overflow: material.TextOverflow.ellipsis,
                ),
              ),
              material.SizedBox(
                width: 48,
                child: material.Text(
                  r.isGrantable,
                  style: material.TextStyle(
                    fontSize: 11,
                    color: theme.mutedForeground,
                  ),
                  textAlign: material.TextAlign.right,
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
