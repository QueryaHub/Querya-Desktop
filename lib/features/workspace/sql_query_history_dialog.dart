import 'package:flutter/widgets.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Shows recent SQL for this connection + database; choosing a row replaces the editor text
/// or prompts if the editor has uncommitted content.
void showSqlQueryHistoryDialog({
  required BuildContext context,
  required int connectionId,
  String? databaseName,
  required material.TextEditingController sqlController,
  void Function(String sql)? onOpenInNewTab,
  @visibleForTesting Future<List<SqlQueryHistoryEntry>> Function()? loadHistory,
}) {
  showAppDialog<void>(
    context: context,
    builder: (ctx) => _SqlQueryHistoryDialogContent(
      connectionId: connectionId,
      databaseName: databaseName,
      sqlController: sqlController,
      onOpenInNewTab: onOpenInNewTab,
      loadHistory: loadHistory,
    ),
  );
}

enum _HistoryApplyAction {
  replace,
  openInNewTab,
  copy,
}

class _SqlQueryHistoryDialogContent extends material.StatefulWidget {
  const _SqlQueryHistoryDialogContent({
    required this.connectionId,
    required this.databaseName,
    required this.sqlController,
    this.onOpenInNewTab,
    this.loadHistory,
  });

  final int connectionId;
  final String? databaseName;
  final material.TextEditingController sqlController;
  final void Function(String sql)? onOpenInNewTab;
  final Future<List<SqlQueryHistoryEntry>> Function()? loadHistory;

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
    if (widget.loadHistory != null) {
      return widget.loadHistory!();
    }
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

  static String _previewOneLine(String sql) => previewSqlOneLine(sql);

  static String? _formatWhen(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return null;
    String z(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${z(t.month)}-${z(t.day)} ${z(t.hour)}:${z(t.minute)}';
  }

  Future<void> _confirmClear() async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 400),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              const Text('Clear query history?').semiBold().large(),
              const Gap(8),
              const Text(
                'Removes saved SQL for this connection and database. This cannot be undone.',
              ).muted().small(),
              const Gap(20),
              material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  QueryaButton.ghost(
                    label: 'Cancel',
                    onPressed: () => material.Navigator.of(ctx).pop(false),
                    size: QueryaControlSize.lg,
                  ),
                  const Gap(8),
                  QueryaButton.destructive(
                    label: 'Clear',
                    onPressed: () => material.Navigator.of(ctx).pop(true),
                    size: QueryaControlSize.lg,
                  ),
                ],
              ),
            ],
          ),
        ),
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

  void _applyDirectly(String text) {
    widget.sqlController.value = material.TextEditingValue(
      text: text,
      selection: material.TextSelection.collapsed(offset: text.length),
    );
    material.Navigator.of(context).pop();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(
      context: context,
      message: 'Query copied to clipboard',
      variant: AppToastVariant.success,
    );
  }

  void _openInNewTab(String text) {
    widget.onOpenInNewTab?.call(text);
    material.Navigator.of(context).pop();
  }

  Future<void> _onEntryTapped(SqlQueryHistoryEntry e) async {
    final current = widget.sqlController.text;
    final isEditorEmpty = current.trim().isEmpty;
    final isSame = current.trim() == e.sqlText.trim();

    if (isEditorEmpty || isSame) {
      _applyDirectly(e.sqlText);
      return;
    }

    final action = await _confirmOverwrite(e.sqlText);
    if (!mounted || action == null) return;

    switch (action) {
      case _HistoryApplyAction.replace:
        _applyDirectly(e.sqlText);
        break;
      case _HistoryApplyAction.openInNewTab:
        _openInNewTab(e.sqlText);
        break;
      case _HistoryApplyAction.copy:
        await _copyToClipboard(e.sqlText);
        break;
    }
  }

  Future<_HistoryApplyAction?> _confirmOverwrite(String sql) async {
    return showAppDialog<_HistoryApplyAction>(
      context: context,
      builder: (ctx) => QueryaDialogCard(
        constraints: const material.BoxConstraints(maxWidth: 440),
        child: material.Padding(
          padding: const material.EdgeInsets.all(20),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              const Text('Replace editor content?').semiBold().large(),
              const Gap(8),
              const Text(
                'The active tab already contains query text. Overwriting it will discard unsaved text.',
              ).muted().small(),
              const Gap(20),
              material.Align(
                alignment: material.Alignment.centerRight,
                child: material.Wrap(
                  alignment: material.WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    QueryaButton.ghost(
                      label: 'Cancel',
                      onPressed: () => material.Navigator.of(ctx).pop(null),
                      size: QueryaControlSize.lg,
                    ),
                    QueryaButton.secondary(
                      label: 'Copy to Clipboard',
                      onPressed: () => material.Navigator.of(ctx)
                          .pop(_HistoryApplyAction.copy),
                      size: QueryaControlSize.lg,
                    ),
                    if (widget.onOpenInNewTab != null)
                      QueryaButton.secondary(
                        label: 'Open in New Tab',
                        onPressed: () => material.Navigator.of(ctx)
                            .pop(_HistoryApplyAction.openInNewTab),
                        size: QueryaControlSize.lg,
                      ),
                    QueryaButton.destructive(
                      label: 'Replace',
                      onPressed: () => material.Navigator.of(ctx)
                          .pop(_HistoryApplyAction.replace),
                      size: QueryaControlSize.lg,
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

  @override
  material.Widget build(material.BuildContext context) {
    final scheme = context.colors;
    return QueryaDialogCard(
      constraints: WindowLayout.dialogConstraints(
        context,
        maxWidth: 520,
        minWidth: 320,
        maxHeight: 440,
      ),
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
                  ).muted().small(),
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
                        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
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
                      ).muted().small(),
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
                          QueryaDivider(height: 1, color: scheme.border),
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final when = _formatWhen(e.recordedAt);
                        return material.Material(
                          color: material.Colors.transparent,
                          child: material.InkWell(
                            onTap: () => unawaited(_onEntryTapped(e)),
                            child: material.Padding(
                              padding: const material.EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: material.Row(
                                children: [
                                  material.Expanded(
                                    child: material.Column(
                                      crossAxisAlignment:
                                          material.CrossAxisAlignment.start,
                                      children: [
                                        material.Text(
                                          _previewOneLine(e.sqlText),
                                          maxLines: 2,
                                          overflow:
                                              material.TextOverflow.ellipsis,
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
                                  const Gap(8),
                                  QueryaButton.icon(
                                    icon: material.Icons.copy_rounded,
                                    tooltip: 'Copy to clipboard',
                                    size: QueryaControlSize.sm,
                                    onPressed: () => unawaited(_copyToClipboard(e.sqlText)),
                                  ),
                                  if (widget.onOpenInNewTab != null) ...[
                                    const Gap(4),
                                    QueryaButton.icon(
                                      icon: material.Icons.open_in_new_rounded,
                                      tooltip: 'Open in new tab',
                                      size: QueryaControlSize.sm,
                                      onPressed: () => _openInNewTab(e.sqlText),
                                    ),
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
                  QueryaButton.ghost(
                    label: 'Clear history',
                    onPressed: () => unawaited(_confirmClear()),
                    size: QueryaControlSize.lg,
                  ),
                  const Spacer(),
                  QueryaButton.ghost(
                    label: 'Close',
                    onPressed: () => material.Navigator.of(context).pop(),
                    size: QueryaControlSize.lg,
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

/// Longest one-line preview kept whole; longer text is cut to
/// [_previewKeep] characters plus an ellipsis.
const int _previewMax = 96;
const int _previewKeep = 93;

/// Same set as the regex `\s` (what the old `replaceAll(RegExp(r'\s+'), ' ')`
/// collapsed).
bool _isPreviewWhitespace(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// One-line, whitespace-collapsed, trimmed preview of [sql] for a list row.
///
/// Reads only as far as it needs: a 100 KB migration is cut after about a
/// hundred characters instead of being copied whole by a regex replace (#1545).
@visibleForTesting
String previewSqlOneLine(String sql) {
  final out = StringBuffer();
  var length = 0;
  var pendingSpace = false;
  for (var i = 0; i < sql.length; i++) {
    if (_isPreviewWhitespace(sql.codeUnitAt(i))) {
      pendingSpace = length > 0;
      continue;
    }
    if (pendingSpace) {
      out.writeCharCode(0x20);
      length++;
      pendingSpace = false;
      if (length > _previewMax) break;
    }
    out.writeCharCode(sql.codeUnitAt(i));
    length++;
    if (length > _previewMax) break;
  }
  final text = out.toString();
  if (length <= _previewMax) return text;
  return '${text.substring(0, _previewKeep)}…';
}
