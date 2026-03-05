import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Database type for new connection.
enum ConnectionType {
  postgresql,
  mysql,
  redis,
  mongodb,
}

extension ConnectionTypeX on ConnectionType {
  String get label => switch (this) {
        ConnectionType.postgresql => 'PostgreSQL',
        ConnectionType.mysql => 'MySQL',
        ConnectionType.redis => 'Redis',
        ConnectionType.mongodb => 'MongoDB',
      };
  material.IconData get icon => switch (this) {
        ConnectionType.postgresql => material.Icons.storage_rounded,
        ConnectionType.mysql => material.Icons.table_chart_rounded,
        ConnectionType.redis => material.Icons.memory_rounded,
        ConnectionType.mongodb => material.Icons.eco_rounded,
      };
  /// Asset path for custom icon (from Downloads).
  String? get iconAsset => switch (this) {
        ConnectionType.postgresql => 'assets/images/postgresql_icon.png',
        ConnectionType.mysql => 'assets/images/mysql_icon.png',
        ConnectionType.redis => 'assets/images/redis_icon.png',
        ConnectionType.mongodb => 'assets/images/mongodb_icon.png',
      };
  bool get isSql => this == ConnectionType.postgresql || this == ConnectionType.mysql;
}

const _sqlTypes = [ConnectionType.postgresql, ConnectionType.mysql];
const _noSqlTypes = [ConnectionType.redis, ConnectionType.mongodb];
const _allTypes = [ConnectionType.postgresql, ConnectionType.mysql, ConnectionType.redis, ConnectionType.mongodb];

enum _Category { all, sql, nosql }

/// Shows a dialog to choose database type (PostgreSQL, MySQL, Redis, MongoDB).
/// Returns the selected type or null if cancelled.
Future<ConnectionType?> showNewConnectionDialog(BuildContext context) {
  return showDialog<ConnectionType>(
    context: context,
    barrierColor: material.Colors.black54,
    builder: (context) => const material.Dialog(
      backgroundColor: material.Colors.transparent,
      insetPadding: material.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: _NewConnectionDialogContent(),
    ),
  );
}

class _NewConnectionDialogContent extends material.StatefulWidget {
  const _NewConnectionDialogContent();

  @override
  material.State<_NewConnectionDialogContent> createState() => _NewConnectionDialogContentState();
}

class _NewConnectionDialogContentState extends material.State<_NewConnectionDialogContent> {
  _Category _category = _Category.all;
  ConnectionType? _selectedType;
  final _searchController = material.TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ConnectionType> get _categoryTypes => switch (_category) {
        _Category.all => _allTypes,
        _Category.sql => _sqlTypes,
        _Category.nosql => _noSqlTypes,
      };

  List<ConnectionType> get _filteredTypes {
    if (_searchQuery.trim().isEmpty) return _categoryTypes;
    final q = _searchQuery.trim().toLowerCase();
    return _categoryTypes.where((t) => t.label.toLowerCase().contains(q)).toList();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final radius = Theme.of(context).radiusXxl;
    return material.Container(
      constraints: const material.BoxConstraints(maxWidth: 740, minHeight: 380),
      decoration: material.BoxDecoration(
        color: theme.popover,
        borderRadius: material.BorderRadius.circular(radius),
        border: material.Border.all(color: theme.muted),
      ),
      child: material.ConstrainedBox(
        constraints: const material.BoxConstraints(maxWidth: 740, minHeight: 380),
        child: material.ClipRRect(
          borderRadius: material.BorderRadius.circular(radius),
          child: material.SizedBox(
            height: 520,
            child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.fromLTRB(24, 24, 24, 8),
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
                      border: material.Border.all(color: theme.border.withValues(alpha: 0.4)),
                    ),
                    padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            material.Expanded(
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Container(
                    width: 140,
                    decoration: material.BoxDecoration(
                      border: material.Border(
                        right: material.BorderSide(
                          color: theme.border.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    child: material.ListView(
                      padding: const material.EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _CategoryTile(
                          label: 'All',
                          icon: material.Icons.dns_rounded,
                          selected: _category == _Category.all,
                          onTap: () => setState(() => _category = _Category.all),
                          theme: theme,
                        ),
                        _CategoryTile(
                          label: 'SQL',
                          icon: material.Icons.table_chart_rounded,
                          selected: _category == _Category.sql,
                          onTap: () => setState(() => _category = _Category.sql),
                          theme: theme,
                        ),
                        _CategoryTile(
                          label: 'NoSQL',
                          icon: material.Icons.memory_rounded,
                          selected: _category == _Category.nosql,
                          onTap: () => setState(() => _category = _Category.nosql),
                          theme: theme,
                        ),
                      ],
                    ),
                  ),
                  material.Expanded(
                    child: material.LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 12.0;
                        const crossAxisCount = 4;
                        final cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                        const cardHeight = 132.0;
                        return material.Padding(
                          padding: const material.EdgeInsets.all(16),
                          child: material.GridView.count(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: spacing,
                            crossAxisSpacing: spacing,
                            childAspectRatio: cardWidth / cardHeight,
                            shrinkWrap: true,
                            physics: const material.ClampingScrollPhysics(),
                            children: [
                              for (final t in _filteredTypes)
                                _DbTypeCard(
                                  type: t,
                                  theme: theme,
                                  selected: _selectedType == t,
                                  onTap: () => setState(() => _selectedType = t),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                  GhostButton(
                    onPressed: () => material.Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const material.SizedBox(width: 12),
                  PrimaryButton(
                    onPressed: _selectedType == null
                        ? null
                        : () => material.Navigator.of(context).pop(_selectedType),
                    child: const Text('Next'),
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final material.IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme theme;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Material(
      color: selected ? theme.muted.withValues(alpha: 0.35) : material.Colors.transparent,
      child: material.InkWell(
        onTap: onTap,
        child: material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: material.Row(
            children: [
              material.Icon(icon, size: 20, color: theme.mutedForeground),
              const material.SizedBox(width: 14),
              selected ? Text(label).semiBold().small() : Text(label).small(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DbTypeCard extends material.StatefulWidget {
  const _DbTypeCard({
    required this.type,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ConnectionType type;
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
          duration: const Duration(milliseconds: 120),
          curve: material.Curves.easeOut,
          padding: const material.EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: material.BoxDecoration(
            color: highlighted ? t.muted.withValues(alpha: 0.4) : t.muted.withValues(alpha: 0.12),
            borderRadius: material.BorderRadius.circular(10),
            border: material.Border.all(
              color: widget.selected ? t.primary.withValues(alpha: 0.6) : t.border.withValues(alpha: 0.35),
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            mainAxisAlignment: material.MainAxisAlignment.center,
            children: [
              material.SizedBox(
                width: 56,
                height: 56,
                child: widget.type.iconAsset != null
                    ? material.Image.asset(
                        widget.type.iconAsset!,
                        fit: material.BoxFit.contain,
                        filterQuality: material.FilterQuality.medium,
                      )
                    : material.Icon(widget.type.icon, size: 56, color: t.primary),
              ),
              const material.SizedBox(height: 10),
              Text(widget.type.label).semiBold().small(),
            ],
          ),
        ),
      ),
    );
  }
}
