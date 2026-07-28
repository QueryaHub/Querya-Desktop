import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/features/settings/preferences_appearance_section.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/features/settings/preferences_extensions_section.dart';
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

class _PreferencesDialogContentState
    extends material.State<_PreferencesDialogContent> {
  bool _loading = true;
  bool _checkUpdatesOnStartup = true;
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
    final startup = await AppSettings.instance.getCheckForUpdatesOnStartup();
    final pg = await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds();
    final my = await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds();
    final rows = await AppSettings.instance.getSqlResultMaxRows();
    final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
    final font = await AppSettings.instance.getSqlEditorFontSize();
    if (!mounted) return;
    setState(() {
      _checkUpdatesOnStartup = startup;
      _pgTimeout = pg;
      _mysqlTimeout = my;
      _maxRows = rows;
      _historyMax = hist;
      _fontSize = font;
      _loading = false;
    });
  }

  Future<void> _setCheckUpdatesOnStartup(bool enabled) async {
    setState(() => _checkUpdatesOnStartup = enabled);
    await AppSettings.instance.setCheckForUpdatesOnStartup(enabled);
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
    final onPopover = theme.popoverForeground;
    return material.DefaultTextStyle(
      style: material.TextStyle(color: onPopover),
      child: material.IconTheme(
        data: material.IconThemeData(color: onPopover),
        child: material.Container(
          constraints: WindowLayout.dialogConstraints(
            context,
            maxWidth: WindowLayout.preferencesDialogMaxWidth,
            minWidth: WindowLayout.preferencesDialogMinWidth,
            maxHeight: WindowLayout.preferencesDialogMaxHeight,
          ),
          decoration: material.BoxDecoration(
            color: theme.popover,
            borderRadius: material.BorderRadius.circular(radius),
            border: material.Border.all(color: theme.border),
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
                      const Text('Preferences').large().semiBold().foreground(),
                      const material.SizedBox(height: 6),
                      const PreferencesHint(
                        'Changes apply immediately. SQL timeouts are global for all connections of that type.',
                      ),
                    ],
                  ),
                ),
                material.Expanded(
                  child: material.SingleChildScrollView(
                    padding: const material.EdgeInsets.symmetric(
                        horizontal: 24, vertical: 8),
                    child: _loading
                        ? const material.Center(
                            child: material.Padding(
                              padding: material.EdgeInsets.all(24),
                              child: material.CircularProgressIndicator(),
                            ),
                          )
                        : material.Column(
                            crossAxisAlignment:
                                material.CrossAxisAlignment.start,
                            children: [
                              const Text('General')
                                  .semiBold()
                                  .small()
                                  .foreground(),
                              const material.SizedBox(height: 8),
                              PreferencesCheckboxRow(
                                value: _checkUpdatesOnStartup,
                                title: const Text(
                                  'Automatically check for updates on startup',
                                ).small(),
                                subtitle: const Text(
                                  'Queries GitHub Releases silently when Querya starts.',
                                ).muted().xSmall(),
                                onChanged: (v) {
                                  unawaited(_setCheckUpdatesOnStartup(v));
                                },
                              ),
                              const material.SizedBox(height: 24),
                              const PreferencesAppearanceSection(),
                              const material.SizedBox(height: 24),
                              const PreferencesExtensionsSection(),
                              const material.SizedBox(height: 24),
                              const Text('SQL — PostgreSQL')
                                  .semiBold()
                                  .small()
                                  .foreground(),
                              const material.SizedBox(height: 8),
                              PreferencesFieldRow(
                                label: 'Statement timeout',
                                control: SqlStatementTimeoutDropdown(
                                  value: _pgTimeout,
                                  expandToParent: true,
                                  onChanged: (v) => unawaited(_setPg(v)),
                                ),
                              ),
                              const material.SizedBox(height: 24),
                              const Text('SQL — MySQL / MariaDB')
                                  .semiBold()
                                  .small()
                                  .foreground(),
                              const material.SizedBox(height: 8),
                              PreferencesFieldRow(
                                label: 'Statement timeout',
                                control: SqlStatementTimeoutDropdown(
                                  value: _mysqlTimeout,
                                  expandToParent: true,
                                  onChanged: (v) => unawaited(_setMysql(v)),
                                ),
                              ),
                              const material.SizedBox(height: 24),
                              const Text('SQL editor')
                                  .semiBold()
                                  .small()
                                  .foreground(),
                              const material.SizedBox(height: 8),
                              PreferencesFieldRow(
                                label: 'Max rows in results',
                                control: PreferencesDropdownMenu<int>(
                                  value: _maxRows,
                                  onSelected: (v) {
                                    if (v != null) unawaited(_setMaxRows(v));
                                  },
                                  entries: [
                                    for (final n in kSqlResultMaxRowsPresets)
                                      material.DropdownMenuEntry(
                                        value: n,
                                        label: '$n',
                                      ),
                                  ],
                                ),
                              ),
                              const material.SizedBox(height: 12),
                              PreferencesFieldRow(
                                label: 'Query history limit',
                                hint:
                                    'Per connection and database; oldest queries are dropped.',
                                control: PreferencesDropdownMenu<int>(
                                  value: _historyMax,
                                  onSelected: (v) {
                                    if (v != null) {
                                      unawaited(_setHistoryMax(v));
                                    }
                                  },
                                  entries: [
                                    for (final n
                                        in kSqlHistoryMaxEntriesPresets)
                                      material.DropdownMenuEntry(
                                        value: n,
                                        label: '$n entries',
                                      ),
                                  ],
                                ),
                              ),
                              const material.SizedBox(height: 12),
                              PreferencesFieldRow(
                                label: 'Font size',
                                control: PreferencesDropdownMenu<double>(
                                  value: _fontSize,
                                  onSelected: (v) {
                                    if (v != null) unawaited(_setFont(v));
                                  },
                                  entries: const [
                                    material.DropdownMenuEntry(
                                      value: 11.0,
                                      label: '11 pt',
                                    ),
                                    material.DropdownMenuEntry(
                                      value: 12.0,
                                      label: '12 pt',
                                    ),
                                    material.DropdownMenuEntry(
                                      value: 13.0,
                                      label: '13 pt',
                                    ),
                                    material.DropdownMenuEntry(
                                      value: 14.0,
                                      label: '14 pt',
                                    ),
                                    material.DropdownMenuEntry(
                                      value: 16.0,
                                      label: '16 pt',
                                    ),
                                    material.DropdownMenuEntry(
                                      value: 18.0,
                                      label: '18 pt',
                                    ),
                                  ],
                                ),
                              ),
                              const material.SizedBox(height: 16),
                              const PreferencesHint(
                                'Preferences are stored locally in SQLite (non-secret keys only).',
                              ),
                            ],
                          ),
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
        ),
      ),
    );
  }
}
