import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

void showPreferencesDialog(BuildContext context) {
  showAppDialog<void>(
    context: context,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: const _PreferencesDialogContent(),
    ),
  );
}

class _PreferencesDialogContent extends material.StatefulWidget {
  const _PreferencesDialogContent();

  @override
  material.State<_PreferencesDialogContent> createState() =>
      _PreferencesDialogContentState();
}

class _PreferencesDialogContentState extends material.State<_PreferencesDialogContent> {
  bool _loading = true;
  int? _pgTimeout;
  int? _mysqlTimeout;
  int _maxRows = kDefaultSqlResultMaxRows;
  int _historyMax = kDefaultSqlHistoryMaxEntries;
  double _fontSize = kDefaultSqlEditorFontSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pg = await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds();
    final my = await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds();
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    setState(() {
      _pgTimeout = pg;
      _mysqlTimeout = my;
      _maxRows = rows;
      _historyMax = hist;
      _fontSize = font;
      _loading = false;
    });
  }

  Future<void> _setPg(int? v) async {
    setState(() => _pgTimeout = v);
    await AppSettings.instance.setPostgresSqlStmtTimeoutSeconds(v);
  }

  Future<void> _setMysql(int? v) async {
    setState(() => _mysqlTimeout = v);
    await AppSettings.instance.setMysqlSqlStmtTimeoutSeconds(v);
  }

  Future<void> _setMaxRows(int v) async {
    setState(() => _maxRows = v);
    await AppSettings.instance.setSqlResultMaxRows(v);
  }

  Future<void> _setFont(double v) async {
    setState(() => _fontSize = v);
    await AppSettings.instance.setSqlEditorFontSize(v);
  }

  Future<void> _setHistoryMax(int v) async {
    setState(() => _historyMax = v);
    await AppSettings.instance.setSqlHistoryMaxEntries(v);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Container(
      constraints: const material.BoxConstraints(
        maxWidth: 480,
        minWidth: 360,
        maxHeight: 560,
      ),
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
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Preferences').large().semiBold(),
                  const material.SizedBox(height: 6),
                  // ignore: prefer_const_constructors — TextStyle via shadcn extensions
                  Text(
                    'Changes apply immediately. SQL timeouts are global for all connections of that type.',
                  ).muted().small(),
                ],
              ),
            ),
            material.Expanded(
              child: material.SingleChildScrollView(
                padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _loading
                    ? const material.Center(
                        child: material.Padding(
                          padding: material.EdgeInsets.all(24),
                          child: material.CircularProgressIndicator(),
                        ),
                      )
                    : material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          const Text('SQL — PostgreSQL').semiBold().small(),
                          const material.SizedBox(height: 8),
                          material.Row(
                            children: [
                              const Text('Statement timeout').small(),
                              const material.SizedBox(width: 12),
                              SqlStatementTimeoutDropdown(
                                value: _pgTimeout,
                                onChanged: (v) => unawaited(_setPg(v)),
                              ),
                            ],
                          ),
                          const material.SizedBox(height: 24),
                          const Text('SQL — MySQL / MariaDB').semiBold().small(),
                          const material.SizedBox(height: 8),
                          material.Row(
                            children: [
                              const Text('Statement timeout').small(),
                              const material.SizedBox(width: 12),
                              SqlStatementTimeoutDropdown(
                                value: _mysqlTimeout,
                                onChanged: (v) => unawaited(_setMysql(v)),
                              ),
                            ],
                          ),
                          const material.SizedBox(height: 24),
                          const Text('SQL editor').semiBold().small(),
                          const material.SizedBox(height: 8),
                          material.Row(
                            children: [
                              const Text('Max rows in results').small(),
                              const material.SizedBox(width: 12),
                              material.DropdownButton<int>(
                                value: _maxRows,
                                onChanged: (v) {
                                  if (v != null) unawaited(_setMaxRows(v));
                                },
                                items: [
                                  for (final n in kSqlResultMaxRowsPresets)
                                    material.DropdownMenuItem(
                                      value: n,
                                      child: material.Text('$n'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const material.SizedBox(height: 12),
                          material.Row(
                            crossAxisAlignment: material.CrossAxisAlignment.start,
                            children: [
                              material.Padding(
                                padding: const material.EdgeInsets.only(top: 8),
                                child: const Text('Query history limit').small(),
                              ),
                              const material.SizedBox(width: 12),
                              material.Expanded(
                                child: material.Column(
                                  crossAxisAlignment:
                                      material.CrossAxisAlignment.start,
                                  children: [
                                    material.DropdownButton<int>(
                                      value: _historyMax,
                                      isExpanded: true,
                                      onChanged: (v) {
                                        if (v != null) {
                                          unawaited(_setHistoryMax(v));
                                        }
                                      },
                                      items: [
                                        for (final n
                                            in kSqlHistoryMaxEntriesPresets)
                                          material.DropdownMenuItem(
                                            value: n,
                                            child: material.Text('$n entries'),
                                          ),
                                      ],
                                    ),
                                    const material.SizedBox(height: 4),
                                    const Text(
                                      'Per connection and database; oldest queries are dropped.',
                                    ).muted().xSmall(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const material.SizedBox(height: 12),
                          material.Row(
                            children: [
                              const Text('Font size').small(),
                              const material.SizedBox(width: 12),
                              material.DropdownButton<double>(
                                value: _fontSize,
                                onChanged: (v) {
                                  if (v != null) unawaited(_setFont(v));
                                },
                                items: const [
                                  material.DropdownMenuItem(
                                    value: 11.0,
                                    child: material.Text('11 pt'),
                                  ),
                                  material.DropdownMenuItem(
                                    value: 12.0,
                                    child: material.Text('12 pt'),
                                  ),
                                  material.DropdownMenuItem(
                                    value: 13.0,
                                    child: material.Text('13 pt'),
                                  ),
                                  material.DropdownMenuItem(
                                    value: 14.0,
                                    child: material.Text('14 pt'),
                                  ),
                                  material.DropdownMenuItem(
                                    value: 16.0,
                                    child: material.Text('16 pt'),
                                  ),
                                  material.DropdownMenuItem(
                                    value: 18.0,
                                    child: material.Text('18 pt'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const material.SizedBox(height: 16),
                          // ignore: prefer_const_constructors — TextStyle via shadcn extensions
                          Text(
                            'Preferences are stored locally in SQLite (non-secret keys only).',
                          ).muted().xSmall(),
                        ],
                      ),
              ),
            ),
            material.Container(
              padding: const material.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: material.BoxDecoration(
                border: material.Border(
                  top: material.BorderSide(color: theme.border.withValues(alpha: 0.3)),
                ),
              ),
              child: material.Row(
                mainAxisAlignment: material.MainAxisAlignment.end,
                children: [
                  PrimaryButton(
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
