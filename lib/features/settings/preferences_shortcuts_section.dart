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

class PreferencesShortcutsSection extends StatelessWidget {
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
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = searchQuery.trim().toLowerCase();

    final filtered = q.isEmpty
        ? allShortcuts
        : allShortcuts.where((item) {
            final matchAction = item.action.toLowerCase().contains(q);
            final matchCategory = item.category.toLowerCase().contains(q);
            final matchDesc =
                item.description?.toLowerCase().contains(q) ?? false;
            final matchKeys = item.keys.any((k) => k.toLowerCase().contains(q));
            return matchAction || matchCategory || matchDesc || matchKeys;
          }).toList();

    if (filtered.isEmpty) {
      return material.Padding(
        padding: const material.EdgeInsets.symmetric(vertical: 32),
        child: material.Center(
          child: Text('No shortcuts match "$searchQuery"')
              .muted()
              .small(),
        ),
      );
    }

    final categories = <String, List<ShortcutItem>>{};
    for (final item in filtered) {
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
