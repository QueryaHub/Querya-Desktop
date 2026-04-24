import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows recent SQL for this connection + database; choosing a row replaces the editor text.
void showSqlQueryHistoryDialog({
  required BuildContext context,
  required int connectionId,
  String? databaseName,
  required material.TextEditingController sqlController,
}) {
  showAppDialog<void>(
    context: context,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: _SqlQueryHistoryDialogContent(
        connectionId: connectionId,
        databaseName: databaseName,
        sqlController: sqlController,
      ),
    ),
  );
}

class _SqlQueryHistoryDialogContent extends material.StatefulWidget {
  const _SqlQueryHistoryDialogContent({
    required this.connectionId,
    required this.databaseName,
    required this.sqlController,
  });

  final int connectionId;
  final String? databaseName;
  final material.TextEditingController sqlController;

  @override
  material.State<_SqlQueryHistoryDialogContent> createState() =>
      _SqlQueryHistoryDialogContentState();
}

class _SqlQueryHistoryDialogContentState
    extends material.State<_SqlQueryHistoryDialogContent> {
  late Future<List<SqlQueryHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SqlQueryHistoryEntry>> _load() async {
    final cap = await AppSettings.instance.getSqlHistoryMaxEntries();
    return LocalDb.instance.listSqlQueryHistory(
      connectionId: widget.connectionId,
      databaseName: widget.databaseName,
      limit: cap,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  static String _previewOneLine(String sql) {
    final collapsed = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 96) return collapsed;
    return '${collapsed.substring(0, 93)}…';
  }

  static String? _formatWhen(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return null;
    String z(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${z(t.month)}-${z(t.day)} ${z(t.hour)}:${z(t.minute)}';
  }

  Future<void> _confirmClear() async {
    final ok = await material.showDialog<bool>(
      context: context,
      builder: (ctx) => material.AlertDialog(
        title: const material.Text('Clear query history?'),
        content: const material.Text(
          'Removes saved SQL for this connection and database. This cannot be undone.',
        ),
        actions: [
          material.TextButton(
            onPressed: () => material.Navigator.of(ctx).pop(false),
            child: const material.Text('Cancel'),
          ),
          material.TextButton(
            onPressed: () => material.Navigator.of(ctx).pop(true),
            child: const material.Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await LocalDb.instance.clearSqlQueryHistoryBucket(
      connectionId: widget.connectionId,
      databaseName: widget.databaseName,
    );
    if (!mounted) return;
    _reload();
  }

  void _apply(SqlQueryHistoryEntry e) {
    final text = e.sqlText;
    widget.sqlController.value = material.TextEditingValue(
      text: text,
      selection: material.TextSelection.collapsed(offset: text.length),
    );
    material.Navigator.of(context).pop();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Container(
      constraints: const material.BoxConstraints(
        maxWidth: 520,
        minWidth: 320,
        maxHeight: 440,
      ),
      decoration: material.BoxDecoration(
        color: scheme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: scheme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Query history').large().semiBold(),
                  const material.SizedBox(height: 4),
                  const Text(
                    'Successful runs from this workspace (newest first).',
                  ).muted()
                      .small(),
                ],
              ),
            ),
            material.Expanded(
              child: material.FutureBuilder<List<SqlQueryHistoryEntry>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != material.ConnectionState.done) {
                    return const material.Center(
                      child: material.Padding(
                        padding: material.EdgeInsets.all(24),
                        child: material.CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return material.Padding(
                      padding: const material.EdgeInsets.all(20),
                      child: Text(
                        'Could not load history: ${snap.error}',
                        style: material.TextStyle(color: scheme.destructive),
                      ).small(),
                    );
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return material.Center(
                      child: const Text(
                        'No queries yet. Run SQL to build history.',
                      ).muted()
                          .small(),
                    );
                  }
                  return material.Scrollbar(
                    child: material.ListView.separated(
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          material.Divider(height: 1, color: scheme.border),
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final when = _formatWhen(e.recordedAt);
                        return material.Material(
                          color: material.Colors.transparent,
                          child: material.InkWell(
                            onTap: () => _apply(e),
                            child: material.Padding(
                              padding: const material.EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: material.Column(
                                crossAxisAlignment:
                                    material.CrossAxisAlignment.start,
                                children: [
                                  material.Text(
                                    _previewOneLine(e.sqlText),
                                    maxLines: 2,
                                    overflow: material.TextOverflow.ellipsis,
                                    style: material.TextStyle(
                                      fontFamily: QueryaTypography.mono,
                                      fontSize: 12,
                                      color: scheme.foreground,
                                    ),
                                  ),
                                  if (when != null) ...[
                                    const material.SizedBox(height: 4),
                                    Text(when).muted().xSmall(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: material.Row(
                children: [
                  GhostButton(
                    onPressed: () => unawaited(_confirmClear()),
                    child: const Text('Clear history'),
                  ),
                  const Spacer(),
                  OutlineButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Close'),
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
