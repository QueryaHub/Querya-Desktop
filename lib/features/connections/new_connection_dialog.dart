import 'dart:math' as math;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Database type for built-in new connections.
enum ConnectionType {
  postgresql,
  mysql,
  redis,
  mongodb,
  sqlite,
}

extension ConnectionTypeX on ConnectionType {
  String get label => switch (this) {
        ConnectionType.postgresql => 'PostgreSQL',
        ConnectionType.mysql => 'MySQL',
        ConnectionType.redis => 'Redis',
        ConnectionType.mongodb => 'MongoDB',
        ConnectionType.sqlite => 'SQLite',
      };
  material.IconData get icon => QueryaIcons.connectionIcon(name);

  /// Asset path for custom icon (from Downloads).
  String? get iconAsset => QueryaIcons.connectionAsset(name);
  bool get isSql =>
      this == ConnectionType.postgresql ||
      this == ConnectionType.mysql ||
      this == ConnectionType.sqlite;
}

enum _Category { all, sql, nosql }

/// Shows a dialog to choose database type (built-in + installed extension drivers).
Future<ConnectionTypeChoice?> showNewConnectionDialog(
  material.BuildContext context,
) async {
  await LocalExtensionRegistry.instance.load();
  if (!context.mounted) return null;
  return showAppDialog<ConnectionTypeChoice>(
    context: context,
    builder: (context) => material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: WindowLayout.dialogSymmetricInsets(context),
      child: const _NewConnectionDialogContent(),
    ),
  );
}

class _NewConnectionDialogContent extends material.StatefulWidget {
  const _NewConnectionDialogContent();

  @override
  material.State<_NewConnectionDialogContent> createState() =>
      _NewConnectionDialogContentState();
}

class _NewConnectionDialogContentState
    extends material.State<_NewConnectionDialogContent> {
  _Category _category = _Category.all;
  ConnectionTypeChoice? _selected;
  final _searchController = material.TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ConnectionTypeChoice> get _categoryTypes => switch (_category) {
        _Category.all => ExtensionDriverCatalog.allChoices(),
        _Category.sql => ExtensionDriverCatalog.sqlChoices(),
        _Category.nosql => ExtensionDriverCatalog.noSqlChoices(),
      };

  List<ConnectionTypeChoice> get _filteredTypes {
    if (_searchQuery.trim().isEmpty) return _categoryTypes;
    final q = _searchQuery.trim().toLowerCase();
    return _categoryTypes
        .where((t) => t.label.toLowerCase().contains(q))
        .toList();
  }

  bool _sameChoice(ConnectionTypeChoice? a, ConnectionTypeChoice? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return switch ((a, b)) {
      (BuiltInConnectionType a, BuiltInConnectionType b) => a.type == b.type,
      (ExtensionDriverChoice a, ExtensionDriverChoice b) =>
        a.manifest.id == b.manifest.id &&
            a.driver.driverId == b.driver.driverId,
      _ => false,
    };
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    final dialogMaxW = WindowLayout.newConnectionDialogMaxWidth(context);
    final dialogH = WindowLayout.newConnectionDialogHeight(context);
    final headerPadH = dialogMaxW < 420 ? 16.0 : 24.0;
    final stackFilters = dialogMaxW < 520;

    return material.Container(
      width: dialogMaxW,
      constraints: material.BoxConstraints(
        maxWidth: dialogMaxW,
        maxHeight: dialogH,
        minHeight: math.min(320.0, dialogH),
      ),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ClipRRect(
        borderRadius: material.BorderRadius.circular(radius),
        child: material.SizedBox(
          height: dialogH,
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              material.Padding(
                padding:
                    material.EdgeInsets.fromLTRB(headerPadH, 20, headerPadH, 8),
                child: Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    const Text('Select your database').large().semiBold(),
                    const material.SizedBox(height: 6),
                    const Text(
                      'Create new database connection. Find your database driver in the list below.',
                    ).muted().small(),
                    const material.SizedBox(height: 12),
                    material.Container(
                      decoration: material.BoxDecoration(
                        color: theme.muted.withValues(alpha: 0.2),
                        borderRadius: material.BorderRadius.circular(8),
                        border: material.Border.all(
                            color: theme.border.withValues(alpha: 0.4)),
                      ),
                      padding: const material.EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: material.Row(
                        children: [
                          material.Icon(
                            material.Icons.search_rounded,
                            size: 20,
                            color: theme.mutedForeground,
                          ),
                          const material.SizedBox(width: 10),
                          material.Expanded(
                            child: TextField(
                              controller: _searchController,
                              placeholder: const Text('Search...'),
                              onChanged: (v) => setState(() {
                                _searchQuery = v;
                                if (_selected != null &&
                                    !_filteredTypes.any(
                                        (t) => _sameChoice(t, _selected))) {
                                  _selected = null;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const material.SizedBox(height: 12),
                    _FilterDropdowns(
                      stackVertically: stackFilters,
                      category: _category,
                      selected: _selected,
                      filteredTypes: _filteredTypes,
                      onCategoryChanged: (category) {
                        setState(() {
                          _category = category;
                          if (_selected != null &&
                              !_categoryTypes
                                  .any((t) => _sameChoice(t, _selected))) {
                            _selected = null;
                          }
                        });
                      },
                      onTypeChanged: (type) => setState(() => _selected = type),
                    ),
                  ],
                ),
              ),
              material.Expanded(
                child: material.LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final gridPad = dialogMaxW < 420 ? 12.0 : 16.0;
                    final innerW =
                        math.max(0.0, constraints.maxWidth - gridPad * 2);
                    final crossAxisCount =
                        WindowLayout.dbTypeGridCrossAxisCount(innerW);
                    final cardHeight =
                        WindowLayout.dbTypeCardHeight(context, crossAxisCount);
                    final cardWidth = crossAxisCount > 0
                        ? (innerW - spacing * (crossAxisCount - 1)) /
                            crossAxisCount
                        : innerW;
                    final aspect =
                        cardHeight > 0 ? cardWidth / cardHeight : 1.0;
                    return material.Padding(
                      padding: material.EdgeInsets.all(gridPad),
                      child: _filteredTypes.isEmpty
                          ? material.Center(
                              child:
                                  const Text('No databases match your search.')
                                      .muted()
                                      .small(),
                            )
                          : material.GridView.count(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: spacing,
                              crossAxisSpacing: spacing,
                              childAspectRatio: aspect.clamp(0.4, 4.0),
                              shrinkWrap: true,
                              physics: const material.ClampingScrollPhysics(),
                              children: [
                                for (final t in _filteredTypes)
                                  _DbTypeCard(
                                    choice: t,
                                    theme: theme,
                                    selected: _sameChoice(_selected, t),
                                    onTap: () => setState(() => _selected = t),
                                  ),
                              ],
                            ),
                    );
                  },
                ),
              ),
              material.Container(
                padding: material.EdgeInsets.symmetric(
                  horizontal: headerPadH,
                  vertical: 14,
                ),
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
                      onPressed: _selected == null
                          ? null
                          : () => material.Navigator.of(context).pop(_selected),
                      child: const Text('Next'),
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

class _FilterDropdowns extends StatelessWidget {
  const _FilterDropdowns({
    required this.stackVertically,
    required this.category,
    required this.selected,
    required this.filteredTypes,
    required this.onCategoryChanged,
    required this.onTypeChanged,
  });

  final bool stackVertically;
  final _Category category;
  final ConnectionTypeChoice? selected;
  final List<ConnectionTypeChoice> filteredTypes;
  final void Function(_Category category) onCategoryChanged;
  final void Function(ConnectionTypeChoice? type) onTypeChanged;

  static const _categoryItems = [
    QueryaDropdownItem(
      value: _Category.all,
      label: 'All databases',
      leading: material.Icon(material.Icons.dns_rounded, size: 18),
    ),
    QueryaDropdownItem(
      value: _Category.sql,
      label: 'SQL',
      leading: material.Icon(material.Icons.table_chart_rounded, size: 18),
    ),
    QueryaDropdownItem(
      value: _Category.nosql,
      label: 'NoSQL',
      leading: material.Icon(material.Icons.memory_rounded, size: 18),
    ),
  ];

  @override
  material.Widget build(material.BuildContext context) {
    final categoryField = material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        const Text('Category').small().muted(),
        const material.SizedBox(height: 4),
        QueryaDropdown<_Category>(
          value: category,
          expandToParent: true,
          items: _categoryItems,
          onSelected: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
      ],
    );

    final typeField = material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        const Text('Database type').small().muted(),
        const material.SizedBox(height: 4),
        QueryaDropdown<ConnectionTypeChoice?>(
          value: selected,
          hint: filteredTypes.isEmpty ? 'No matches' : 'Select database…',
          enabled: filteredTypes.isNotEmpty,
          expandToParent: true,
          items: [
            for (final type in filteredTypes)
              QueryaDropdownItem<ConnectionTypeChoice?>(
                value: type,
                label: type.label,
                leading: DriverIcon(
                  filePath: type.iconFile,
                  assetPath: type.iconAsset,
                  size: 18,
                  fallbackIcon: type.icon,
                ),
              ),
          ],
          onSelected: onTypeChanged,
        ),
      ],
    );

    if (stackVertically) {
      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          categoryField,
          const material.SizedBox(height: 10),
          typeField,
        ],
      );
    }

    return material.Row(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Expanded(child: categoryField),
        const material.SizedBox(width: 12),
        material.Expanded(child: typeField),
      ],
    );
  }
}

class _DbTypeCard extends material.StatefulWidget {
  const _DbTypeCard({
    required this.choice,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ConnectionTypeChoice choice;
  final ColorScheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  material.State<_DbTypeCard> createState() => _DbTypeCardState();
}

class _DbTypeCardState extends material.State<_DbTypeCard> {
  bool _hovered = false;

  @override
  material.Widget build(material.BuildContext context) {
    final t = widget.theme;
    final highlighted = widget.selected || _hovered;
    return material.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: material.SystemMouseCursors.click,
      child: material.GestureDetector(
        onTap: widget.onTap,
        child: material.AnimatedContainer(
          duration: context.motionDuration(QueryaMotion.fast),
          curve: context.motionCurve(QueryaMotion.enter),
          padding:
              const material.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: material.BoxDecoration(
            color: highlighted
                ? t.muted.withValues(alpha: 0.4)
                : t.muted.withValues(alpha: 0.12),
            borderRadius: material.BorderRadius.circular(10),
            border: material.Border.all(
              color: widget.selected
                  ? t.primary.withValues(alpha: 0.6)
                  : t.border.withValues(alpha: 0.35),
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              material.Expanded(
                child: material.Center(
                  child: material.SizedBox(
                    width: 52,
                    height: 52,
                    child: DriverIcon(
                      filePath: widget.choice.iconFile,
                      assetPath: widget.choice.iconAsset,
                      size: 52,
                      fallbackIcon: widget.choice.icon,
                    ),
                  ),
                ),
              ),
              const material.SizedBox(height: 6),
              material.LayoutBuilder(
                builder: (context, lc) {
                  return material.SizedBox(
                    height: 38,
                    child: material.FittedBox(
                      fit: material.BoxFit.scaleDown,
                      alignment: material.Alignment.center,
                      child: material.ConstrainedBox(
                        constraints: material.BoxConstraints(
                          maxWidth: math.max(48.0, lc.maxWidth),
                        ),
                        child: material.Text(
                          widget.choice.label,
                          textAlign: material.TextAlign.center,
                          maxLines: 2,
                          overflow: material.TextOverflow.ellipsis,
                          style: material.TextStyle(
                            fontSize: 13,
                            fontWeight: material.FontWeight.w600,
                            height: 1.2,
                            color: t.foreground,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
