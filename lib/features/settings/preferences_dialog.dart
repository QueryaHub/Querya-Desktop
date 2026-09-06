import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/updater/update_manifest.dart';
import 'package:querya_desktop/features/settings/preferences_about_section.dart';
import 'package:querya_desktop/features/settings/preferences_appearance_section.dart';
import 'package:querya_desktop/features/settings/preferences_category.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/features/settings/preferences_extensions_section.dart';
import 'package:querya_desktop/features/settings/preferences_shortcuts_section.dart';
import 'package:querya_desktop/features/settings/sql_statement_timeout_dropdown.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

export 'preferences_category.dart';

/// Opens application preferences in a master-detail dialog.
void showPreferencesDialog(
  BuildContext context, {
  PreferencesCategory? initialCategory,
}) {
  showAppDialog<void>(
    context: context,
    builder: (ctx) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(ctx),
      child: _PreferencesDialogContent(
        initialCategory: initialCategory ?? PreferencesCategory.general,
      ),
    ),
  );
}

class _PreferencesDialogContent extends material.StatefulWidget {
  const _PreferencesDialogContent({
    this.initialCategory = PreferencesCategory.general,
  });

  final PreferencesCategory initialCategory;

  @override
  material.State<_PreferencesDialogContent> createState() =>
      PreferencesDialogContentState();
}

class PreferencesDialogContentState
    extends material.State<_PreferencesDialogContent> {
  late PreferencesCategory _selectedCategory;
  final _searchController = material.TextEditingController();
  final _searchFocusNode = material.FocusNode();
  String _searchQuery = '';

  bool _checkUpdatesOnStartup = true;
  UpdateChannel _updateChannel = UpdateChannel.stable;
  bool _confirmDestructive = true;
  int? _pgTimeout;
  int? _mysqlTimeout;
  int _maxRows = kDefaultSqlResultMaxRows;
  int _historyMax = kDefaultSqlHistoryMaxEntries;
  double _fontSize = kDefaultSqlEditorFontSize;

  PreferencesCategory get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void selectCategory(PreferencesCategory category) {
    setState(() => _selectedCategory = category);
  }

  void setSearchQueryForTest(String query) {
    _searchController.text = query;
    setState(() => _searchQuery = query.trim());
  }

  Future<void> _load() async {
    try {
      final startup = await AppSettings.instance.getCheckForUpdatesOnStartup();
      final channel = await AppSettings.instance.getUpdateChannel();
      final destructive =
          await AppSettings.instance.getConfirmDestructiveOperations();
      final pg = await AppSettings.instance.getPostgresSqlStmtTimeoutSeconds();
      final my = await AppSettings.instance.getMysqlSqlStmtTimeoutSeconds();
      final rows = await AppSettings.instance.getSqlResultMaxRows();
      final hist = await AppSettings.instance.getSqlHistoryMaxEntries();
      final font = await AppSettings.instance.getSqlEditorFontSize();
      if (!mounted) return;
      setState(() {
        _checkUpdatesOnStartup = startup;
        _updateChannel = channel;
        _confirmDestructive = destructive;
        _pgTimeout = pg;
        _mysqlTimeout = my;
        _maxRows = rows;
        _historyMax = hist;
        _fontSize = font;
      });
    } catch (_) {}
  }

  Future<void> _setCheckUpdatesOnStartup(bool enabled) async {
    setState(() => _checkUpdatesOnStartup = enabled);
    await AppSettings.instance.setCheckForUpdatesOnStartup(enabled);
  }

  Future<void> _setUpdateChannel(UpdateChannel channel) async {
    setState(() => _updateChannel = channel);
    await AppSettings.instance.setUpdateChannel(channel);
  }

  Future<void> _setConfirmDestructive(bool enabled) async {
    setState(() => _confirmDestructive = enabled);
    await AppSettings.instance.setConfirmDestructiveOperations(enabled);
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

  int _matchCountForCategory(PreferencesCategory cat) {
    if (_searchQuery.isEmpty) return 0;
    final q = _searchQuery.toLowerCase();
    int count = 0;
    if (cat.label.toLowerCase().contains(q)) count++;
    if (cat.description.toLowerCase().contains(q)) count++;

    switch (cat) {
      case PreferencesCategory.general:
        if ('updates startup automatic release channel stable beta'
            .contains(q)) {
          count++;
        }
      case PreferencesCategory.appearance:
        if ('theme dark light system scaling motion animation interface color'
            .contains(q)) {
          count++;
        }
      case PreferencesCategory.sql:
        if ('font size postgresql mysql statement timeout history destructive drop truncate delete'
            .contains(q)) {
          count++;
        }
      case PreferencesCategory.dataGrid:
        if ('max rows results grid column size formatting safety limits'
            .contains(q)) {
          count++;
        }
      case PreferencesCategory.extensions:
        if ('extensions qext zip package install sideload folder directory'
            .contains(q)) {
          count++;
        }
      case PreferencesCategory.shortcuts:
        final matching = PreferencesShortcutsSection.allShortcuts.where(
          (s) =>
              s.action.toLowerCase().contains(q) ||
              s.keys.any((k) => k.toLowerCase().contains(q)),
        );
        count += matching.length;
      case PreferencesCategory.about:
        if ('about version storage directory cache logs sqlite'
            .contains(q)) {
          count++;
        }
    }
    return count;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final onPopover = theme.popoverForeground;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.keyF, control: true):
            () => _searchFocusNode.requestFocus(),
        const material.SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            () => _searchFocusNode.requestFocus(),
      },
      child: material.DefaultTextStyle(
        style: material.TextStyle(color: onPopover),
        child: material.IconTheme(
          data: material.IconThemeData(color: onPopover),
          child: QueryaDialogCard(
            constraints: WindowLayout.dialogConstraints(
              context,
              maxWidth: WindowLayout.preferencesDialogMaxWidth,
              minWidth: WindowLayout.preferencesDialogMinWidth,
              maxHeight: WindowLayout.preferencesDialogMaxHeight,
            ),
            borderColor: theme.border,
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                // Dialog Header with Title and Search Input
                material.Container(
                  padding: const material.EdgeInsets.fromLTRB(20, 16, 16, 12),
                  decoration: material.BoxDecoration(
                    border: material.Border(
                      bottom: material.BorderSide(
                        color: theme.border.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: material.Row(
                    children: [
                      material.Icon(
                        material.Icons.tune_rounded,
                        size: 20,
                        color: theme.primary,
                      ),
                      const Gap(10),
                      const Text('Preferences').large().semiBold().foreground(),
                      const Gap(20),
                      material.Expanded(
                        child: material.Container(
                          height: 32,
                          padding: const material.EdgeInsets.symmetric(
                              horizontal: 10),
                          decoration: material.BoxDecoration(
                            color: theme.muted.withValues(alpha: 0.25),
                            borderRadius: material.BorderRadius.circular(6),
                            border: material.Border.all(
                              color: _searchQuery.isNotEmpty
                                  ? theme.primary.withValues(alpha: 0.5)
                                  : theme.border.withValues(alpha: 0.25),
                            ),
                          ),
                          child: material.Row(
                            children: [
                              material.Icon(
                                material.Icons.search_rounded,
                                size: 15,
                                color: _searchQuery.isNotEmpty
                                    ? theme.primary
                                    : theme.mutedForeground,
                              ),
                              const Gap(8),
                              material.Expanded(
                                child: material.TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onChanged: (val) {
                                    final q = val.trim();
                                    setState(() {
                                      _searchQuery = q;
                                      if (q.isNotEmpty &&
                                          _matchCountForCategory(
                                                  _selectedCategory) ==
                                              0) {
                                        for (final cat
                                            in PreferencesCategory.values) {
                                          if (_matchCountForCategory(cat) > 0) {
                                            _selectedCategory = cat;
                                            break;
                                          }
                                        }
                                      }
                                    });
                                  },
                                  style: material.TextStyle(
                                    fontSize: 12,
                                    color: theme.foreground,
                                  ),
                                  decoration: material.InputDecoration(
                                    hintText: 'Filter preferences... (Ctrl+F)',
                                    hintStyle: material.TextStyle(
                                      fontSize: 12,
                                      color: theme.mutedForeground
                                          .withValues(alpha: 0.6),
                                    ),
                                    border: material.InputBorder.none,
                                    isDense: true,
                                    contentPadding: material.EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                material.GestureDetector(
                                  behavior: material.HitTestBehavior.opaque,
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: material.Icon(
                                    material.Icons.close_rounded,
                                    size: 14,
                                    color: theme.mutedForeground,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      material.IconButton(
                        icon: const material.Icon(material.Icons.close_rounded,
                            size: 18),
                        padding: material.EdgeInsets.zero,
                        constraints: const material.BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        splashRadius: 16,
                        tooltip: 'Close',
                        onPressed: () => material.Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Master-Detail Body
                material.Expanded(
                  child: material.Row(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                            // Left Category Rail
                            material.Container(
                              width: 184,
                              decoration: material.BoxDecoration(
                                border: material.Border(
                                  right: material.BorderSide(
                                    color: theme.border.withValues(alpha: 0.28),
                                  ),
                                ),
                              ),
                              child: material.SingleChildScrollView(
                                padding: const material.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: material.Column(
                                  crossAxisAlignment:
                                      material.CrossAxisAlignment.stretch,
                                  children: [
                                    for (final cat
                                        in PreferencesCategory.values)
                                      _buildCategoryRailTile(cat, theme),
                                  ],
                                ),
                              ),
                            ),

                            // Right Detail Content Area
                            material.Expanded(
                              child: material.SingleChildScrollView(
                                padding: const material.EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: _buildSelectedCategoryPane(theme),
                              ),
                            ),
                          ],
                        ),
                ),

                // Footer Actions
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: material.BoxDecoration(
                    border: material.Border(
                      top: material.BorderSide(
                        color: theme.border.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  child: material.Row(
                    children: [
                      const material.Expanded(
                        child: PreferencesHint(
                          'Changes apply immediately and persist locally.',
                        ),
                      ),
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

  material.Widget _buildCategoryRailTile(
    PreferencesCategory cat,
    ColorScheme theme,
  ) {
    final isSelected = _selectedCategory == cat;
    final matches = _matchCountForCategory(cat);
    final hasSearch = _searchQuery.isNotEmpty;

    return material.Padding(
      padding: const material.EdgeInsets.only(bottom: 2),
      child: material.Material(
        type: material.MaterialType.transparency,
        child: material.InkWell(
          onTap: () => setState(() => _selectedCategory = cat),
          borderRadius: material.BorderRadius.circular(6),
          child: material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: material.BoxDecoration(
              color: isSelected
                  ? theme.primary.withValues(alpha: 0.12)
                  : material.Colors.transparent,
              borderRadius: material.BorderRadius.circular(6),
            ),
            child: material.Row(
              children: [
                material.Icon(
                  cat.icon,
                  size: 16,
                  color: isSelected ? theme.primary : theme.mutedForeground,
                ),
                const Gap(10),
                material.Expanded(
                  child: material.Text(
                    cat.label,
                    style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? material.FontWeight.w600
                          : material.FontWeight.w400,
                      color: isSelected ? theme.primary : theme.foreground,
                    ),
                  ),
                ),
                if (hasSearch && matches > 0)
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: material.BoxDecoration(
                      color: isSelected
                          ? theme.primary
                          : theme.muted.withValues(alpha: 0.5),
                      borderRadius: material.BorderRadius.circular(10),
                    ),
                    child: material.Text(
                      '$matches',
                      style: material.TextStyle(
                        fontSize: 10,
                        fontWeight: material.FontWeight.w600,
                        color: isSelected
                            ? theme.primaryForeground
                            : theme.foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  material.Widget _buildSelectedCategoryPane(ColorScheme theme) {
    switch (_selectedCategory) {
      case PreferencesCategory.general:
        return _buildGeneralSection(theme);
      case PreferencesCategory.appearance:
        return const PreferencesAppearanceSection();
      case PreferencesCategory.sql:
        return _buildSqlSection(theme);
      case PreferencesCategory.dataGrid:
        return _buildDataGridSection(theme);
      case PreferencesCategory.extensions:
        return const PreferencesExtensionsSection();
      case PreferencesCategory.shortcuts:
        return PreferencesShortcutsSection(searchQuery: _searchQuery);
      case PreferencesCategory.about:
        return const PreferencesAboutSection();
    }
  }

  material.Widget _buildGeneralSection(ColorScheme theme) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('General Settings').semiBold().small().foreground(),
        const material.SizedBox(height: 6),
        const PreferencesHint(
          'Application startup behavior and update release channels.',
        ),
        const material.SizedBox(height: 14),

        PreferencesSwitchRow(
          value: _checkUpdatesOnStartup,
          title: const Text('Check for updates automatically on startup').small(),
          subtitle: const Text(
            'Silently checks GitHub Releases when Querya starts to notify you of new features.',
          ).muted().xSmall(),
          onChanged: (v) => unawaited(_setCheckUpdatesOnStartup(v)),
        ),

        const material.SizedBox(height: 16),
        PreferencesFieldRow(
          label: 'Release channel',
          hint:
              'Stable receives thoroughly tested monthly updates. Beta receives early releases with experimental features.',
          control: PreferencesDropdownMenu<UpdateChannel>(
            value: _updateChannel,
            onSelected: (v) {
              if (v != null) unawaited(_setUpdateChannel(v));
            },
            entries: const [
              material.DropdownMenuEntry(
                value: UpdateChannel.stable,
                label: 'Stable (Recommended)',
              ),
              material.DropdownMenuEntry(
                value: UpdateChannel.dev,
                label: 'Beta / Early Access',
              ),
            ],
          ),
        ),
      ],
    );
  }

  material.Widget _buildSqlSection(ColorScheme theme) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('SQL & Query Execution').semiBold().small().foreground(),
        const material.SizedBox(height: 6),
        const PreferencesHint(
          'Global statement timeouts, editor formatting, and query history.',
        ),
        const material.SizedBox(height: 16),

        PreferencesFieldRow(
          label: 'Editor font size',
          control: PreferencesDropdownMenu<double>(
            value: _fontSize,
            onSelected: (v) {
              if (v != null) unawaited(_setFont(v));
            },
            entries: const [
              material.DropdownMenuEntry(value: 11.0, label: '11 pt'),
              material.DropdownMenuEntry(value: 12.0, label: '12 pt'),
              material.DropdownMenuEntry(value: 13.0, label: '13 pt (Default)'),
              material.DropdownMenuEntry(value: 14.0, label: '14 pt'),
              material.DropdownMenuEntry(value: 16.0, label: '16 pt'),
              material.DropdownMenuEntry(value: 18.0, label: '18 pt'),
            ],
          ),
        ),

        const material.SizedBox(height: 16),
        PreferencesFieldRow(
          label: 'PostgreSQL timeout',
          hint: 'Statement timeout applied to queries on PostgreSQL connections.',
          control: SqlStatementTimeoutDropdown(
            value: _pgTimeout,
            expandToParent: true,
            onChanged: (v) => unawaited(_setPg(v)),
          ),
        ),

        const material.SizedBox(height: 16),
        PreferencesFieldRow(
          label: 'MySQL timeout',
          hint:
              'Max execution time applied to queries on MySQL and MariaDB servers.',
          control: SqlStatementTimeoutDropdown(
            value: _mysqlTimeout,
            expandToParent: true,
            onChanged: (v) => unawaited(_setMysql(v)),
          ),
        ),

        const material.SizedBox(height: 16),
        PreferencesFieldRow(
          label: 'Query history limit',
          hint: 'Per connection and database. Older queries are trimmed automatically.',
          control: PreferencesDropdownMenu<int>(
            value: _historyMax,
            onSelected: (v) {
              if (v != null) unawaited(_setHistoryMax(v));
            },
            entries: [
              for (final n in kSqlHistoryMaxEntriesPresets)
                material.DropdownMenuEntry(
                  value: n,
                  label: '$n entries',
                ),
            ],
          ),
        ),

        const material.SizedBox(height: 16),
        PreferencesSwitchRow(
          value: _confirmDestructive,
          title: const Text('Confirm destructive SQL queries').small(),
          subtitle: const Text(
            'Displays confirmation modal before running DROP, TRUNCATE, or unconditional DELETE queries.',
          ).muted().xSmall(),
          onChanged: (v) => unawaited(_setConfirmDestructive(v)),
        ),
      ],
    );
  }

  material.Widget _buildDataGridSection(ColorScheme theme) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('Data Grid & Results').semiBold().small().foreground(),
        const material.SizedBox(height: 6),
        const PreferencesHint(
          'Configure virtualization limits, column sizing, and result viewing.',
        ),
        const material.SizedBox(height: 16),

        PreferencesFieldRow(
          label: 'Max rows in results',
          hint:
              'Limits row count rendered in the virtualized grid to prevent out-of-memory errors on large queries.',
          control: PreferencesDropdownMenu<int>(
            value: _maxRows,
            onSelected: (v) {
              if (v != null) unawaited(_setMaxRows(v));
            },
            entries: [
              for (final n in kSqlResultMaxRowsPresets)
                material.DropdownMenuEntry(
                  value: n,
                  label: '$n rows',
                ),
            ],
          ),
        ),

        const material.SizedBox(height: 16),
        PreferencesSwitchRow(
          value: _confirmDestructive,
          title: const Text('Confirm DML staging applications').small(),
          subtitle: const Text(
            'Requests confirmation before applying staged row inserts, deletes, or cell updates.',
          ).muted().xSmall(),
          onChanged: (v) => unawaited(_setConfirmDestructive(v)),
        ),
      ],
    );
  }
}
