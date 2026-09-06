import 'dart:io' show Platform;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

class ShortcutItem {
  const ShortcutItem({
    required this.category,
    required this.action,
    required this.keys,
    this.description,
  });

  final String category;
  final String action;
  final List<String> keys;
  final String? description;
}

/// Interactive shortcuts reference table grouped by category with OS-aware keycaps.
class PreferencesShortcutsSection extends material.StatefulWidget {
  const PreferencesShortcutsSection({super.key, this.searchQuery = ''});

  final String searchQuery;

  static bool get _isMac => Platform.isMacOS;
  static String get _modKey => _isMac ? '⌘' : 'Ctrl';

  static List<ShortcutItem> get allShortcuts => [
        // SQL Editor
        ShortcutItem(
          category: 'SQL Editor',
          action: 'Execute query / selection',
          keys: [_modKey, 'Enter'],
          description: 'Runs statement under cursor or selected text',
        ),
        ShortcutItem(
          category: 'SQL Editor',
          action: 'Execute all statements',
          keys: [_modKey, 'Shift', 'Enter'],
          description: 'Runs entire query script sequentially',
        ),
        ShortcutItem(
          category: 'SQL Editor',
          action: 'New query tab',
          keys: [_modKey, 'T'],
          description: 'Opens a new independent SQL tab session',
        ),
        ShortcutItem(
          category: 'SQL Editor',
          action: 'Close current tab',
          keys: [_modKey, 'W'],
          description: 'Prompts to save if uncommitted changes exist',
        ),
        const ShortcutItem(
          category: 'SQL Editor',
          action: 'Next query tab',
          keys: ['Ctrl', 'Tab'],
          description: 'Switches to the next open SQL tab',
        ),
        const ShortcutItem(
          category: 'SQL Editor',
          action: 'Previous query tab',
          keys: ['Ctrl', 'Shift', 'Tab'],
          description: 'Switches to the previous open SQL tab',
        ),
        ShortcutItem(
          category: 'SQL Editor',
          action: 'Query history',
          keys: [_modKey, 'H'],
          description: 'Browse previous queries for this connection',
        ),
        const ShortcutItem(
          category: 'SQL Editor',
          action: 'Format SQL statement',
          keys: ['Shift', 'Alt', 'F'],
          description: 'Formats keywords and statement indentation',
        ),
        const ShortcutItem(
          category: 'SQL Editor',
          action: 'Toggle full-screen editor',
          keys: ['F11'],
          description: 'Maximizes the SQL query workspace area',
        ),

        // Data Grid
        ShortcutItem(
          category: 'Data Grid',
          action: 'Copy cell value',
          keys: [_modKey, 'C'],
          description: 'Copies selected cell value to clipboard',
        ),
        ShortcutItem(
          category: 'Data Grid',
          action: 'Copy with headers',
          keys: [_modKey, 'Shift', 'C'],
          description: 'Copies selection formatted with column names (TSV)',
        ),
        ShortcutItem(
          category: 'Data Grid',
          action: 'Inspect / Edit cell',
          keys: [_modKey, 'I'],
          description: 'Opens popover inspector for JSON, XML, or Text',
        ),
        const ShortcutItem(
          category: 'Data Grid',
          action: 'Set cell to NULL',
          keys: ['Alt', 'N'],
          description: 'Stages NULL value for selected cell(s)',
        ),
        ShortcutItem(
          category: 'Data Grid',
          action: 'Duplicate row',
          keys: [_modKey, 'D'],
          description: 'Duplicates selected row into DML staging buffer',
        ),
        const ShortcutItem(
          category: 'Data Grid',
          action: 'Auto-fit column width',
          keys: ['Double Click Divider'],
          description: 'Sizes column width to fit sampled content',
        ),
        const ShortcutItem(
          category: 'Data Grid',
          action: 'Revert staged cell changes',
          keys: ['Escape'],
          description: 'Discards uncommitted cell edit or inspector',
        ),
        const ShortcutItem(
          category: 'Data Grid',
          action: 'Filter by cell value',
          keys: ['Right Click', 'Filter'],
          description: 'Filters grid by value matching selected cell',
        ),

        // Navigation & App
        ShortcutItem(
          category: 'Navigation & App',
          action: 'Find in Connections / Editor',
          keys: [_modKey, 'F'],
          description: 'Focuses quick search in sidebar tree or editor',
        ),
        ShortcutItem(
          category: 'Navigation & App',
          action: 'Toggle sidebar',
          keys: [_modKey, 'B'],
          description: 'Expands or hides the servers/connections panel',
        ),
        ShortcutItem(
          category: 'Navigation & App',
          action: 'Preferences',
          keys: [_modKey, ','],
          description: 'Opens application settings dialog',
        ),
        const ShortcutItem(
          category: 'Navigation & App',
          action: 'Refresh schema / connection',
          keys: ['F5'],
          description: 'Refreshes databases and table tree',
        ),
        ShortcutItem(
          category: 'Navigation & App',
          action: 'New connection',
          keys: [_modKey, 'N'],
          description: 'Opens connection creation dialog',
        ),
        const ShortcutItem(
          category: 'Navigation & App',
          action: 'Close modal dialog',
          keys: ['Escape'],
          description: 'Dismisses open dialog or popover overlay',
        ),
      ];

  @override
  material.State<PreferencesShortcutsSection> createState() =>
      _PreferencesShortcutsSectionState();
}

class _PreferencesShortcutsSectionState
    extends material.State<PreferencesShortcutsSection> {
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.searchQuery.trim().toLowerCase();

    final all = PreferencesShortcutsSection.allShortcuts;
    final categoriesList = ['All', 'SQL Editor', 'Data Grid', 'Navigation & App'];

    final filtered = all.where((item) {
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      final matchAction = item.action.toLowerCase().contains(q);
      final matchCategory = item.category.toLowerCase().contains(q);
      final matchDesc = item.description?.toLowerCase().contains(q) ?? false;
      final matchKeys = item.keys.any((k) => k.toLowerCase().contains(q));
      return matchAction || matchCategory || matchDesc || matchKeys;
    }).toList();

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        // Category Filter Chips
        material.SingleChildScrollView(
          scrollDirection: material.Axis.horizontal,
          child: material.Row(
            children: [
              for (final cat in categoriesList) ...[
                material.Padding(
                  padding: const material.EdgeInsets.only(right: 6, bottom: 10),
                  child: material.Material(
                    type: material.MaterialType.transparency,
                    child: material.InkWell(
                      onTap: () => setState(() => _selectedCategory = cat),
                      borderRadius: material.BorderRadius.circular(16),
                      child: material.Container(
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: material.BoxDecoration(
                          color: _selectedCategory == cat
                              ? theme.colorScheme.primary.withValues(alpha: 0.16)
                              : theme.colorScheme.muted.withValues(alpha: 0.3),
                          borderRadius: material.BorderRadius.circular(16),
                          border: material.Border.all(
                            color: _selectedCategory == cat
                                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                                : theme.colorScheme.border.withValues(alpha: 0.25),
                          ),
                        ),
                        child: material.Row(
                          mainAxisSize: material.MainAxisSize.min,
                          children: [
                            material.Text(
                              cat,
                              style: material.TextStyle(
                                fontSize: 11,
                                fontWeight: _selectedCategory == cat
                                    ? material.FontWeight.w600
                                    : material.FontWeight.w400,
                                color: _selectedCategory == cat
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.foreground,
                              ),
                            ),
                            const material.SizedBox(width: 4),
                            material.Text(
                              '(${cat == 'All' ? all.length : all.where((s) => s.category == cat).length})',
                              style: material.TextStyle(
                                fontSize: 10,
                                color: _selectedCategory == cat
                                    ? theme.colorScheme.primary.withValues(alpha: 0.8)
                                    : theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (filtered.isEmpty)
          material.Padding(
            padding: const material.EdgeInsets.symmetric(vertical: 32),
            child: material.Center(
              child: Text(widget.searchQuery.isNotEmpty
                      ? 'No shortcuts match "${widget.searchQuery}"'
                      : 'No shortcuts in $_selectedCategory')
                  .muted()
                  .small(),
            ),
          )
        else ...[
          _buildShortcutTable(context, filtered, theme),
        ],
      ],
    );
  }

  material.Widget _buildShortcutTable(
    BuildContext context,
    List<ShortcutItem> items,
    ThemeData theme,
  ) {
    final categories = <String, List<ShortcutItem>>{};
    for (final item in items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        for (final entry in categories.entries) ...[
          material.Padding(
            padding: const material.EdgeInsets.only(top: 8, bottom: 8),
            child: Text(entry.key).semiBold().small().foreground(),
          ),
          material.Container(
            decoration: material.BoxDecoration(
              color: theme.colorScheme.muted.withValues(alpha: 0.16),
              borderRadius: material.BorderRadius.circular(8),
              border: material.Border.all(
                color: theme.colorScheme.border.withValues(alpha: 0.25),
              ),
            ),
            child: material.Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: theme.colorScheme.border.withValues(alpha: 0.18),
                    ),
                  _buildShortcutRow(context, entry.value[i], theme),
                ],
              ],
            ),
          ),
          const material.SizedBox(height: 16),
        ],
      ],
    );
  }

  material.Widget _buildShortcutRow(
    BuildContext context,
    ShortcutItem item,
    ThemeData theme,
  ) {
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                Text(item.action).small().foreground(),
                if (item.description != null) ...[
                  const material.SizedBox(height: 2),
                  Text(item.description!).muted().xSmall(),
                ],
              ],
            ),
          ),
          const material.SizedBox(width: 12),
          material.Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              for (var j = 0; j < item.keys.length; j++) ...[
                if (j > 0)
                  material.Padding(
                    padding: const material.EdgeInsets.symmetric(horizontal: 3),
                    child: const Text('+')
                        .muted()
                        .xSmall(),
                  ),
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: material.BoxDecoration(
                    color: theme.colorScheme.background,
                    borderRadius: material.BorderRadius.circular(4),
                    border: material.Border.all(
                      color: theme.colorScheme.border.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      material.BoxShadow(
                        color: material.Colors.black.withValues(alpha: 0.08),
                        offset: const material.Offset(0, 1),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                  child: material.Text(
                    item.keys[j],
                    style: material.TextStyle(
                      fontFamily: QueryaTypography.mono,
                      fontSize: 11,
                      fontWeight: material.FontWeight.w600,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
