import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Kind of filter autocomplete suggestion.
enum FilterSuggestionKind {
  column,
  operator,
  keyword,
}

/// Autocomplete suggestion model for the Data Grid filter bar.
class FilterSuggestion {
  const FilterSuggestion({
    required this.text,
    required this.kind,
    this.description = '',
    this.insertText,
  });

  final String text;
  final FilterSuggestionKind kind;
  final String description;
  final String? insertText;
}

/// Helper to compute context-aware syntax suggestions for the filter bar.
abstract final class FilterSuggestionEngine {
  static const _operators = [
    FilterSuggestion(text: '=', kind: FilterSuggestionKind.operator, description: 'Equal'),
    FilterSuggestion(text: '!=', kind: FilterSuggestionKind.operator, description: 'Not equal'),
    FilterSuggestion(text: '>', kind: FilterSuggestionKind.operator, description: 'Greater than'),
    FilterSuggestion(text: '>=', kind: FilterSuggestionKind.operator, description: 'Greater or equal'),
    FilterSuggestion(text: '<', kind: FilterSuggestionKind.operator, description: 'Less than'),
    FilterSuggestion(text: '<=', kind: FilterSuggestionKind.operator, description: 'Less or equal'),
    FilterSuggestion(text: 'LIKE', kind: FilterSuggestionKind.operator, description: 'Wildcard match (%_)'),
    FilterSuggestion(text: 'ILIKE', kind: FilterSuggestionKind.operator, description: 'Case-insensitive match'),
    FilterSuggestion(text: 'IN (...)', kind: FilterSuggestionKind.operator, description: 'List inclusion', insertText: "IN ('')"),
    FilterSuggestion(text: 'IS NULL', kind: FilterSuggestionKind.operator, description: 'Null check'),
    FilterSuggestion(text: 'IS NOT NULL', kind: FilterSuggestionKind.operator, description: 'Not null check'),
    FilterSuggestion(text: 'BETWEEN', kind: FilterSuggestionKind.operator, description: 'Range check', insertText: 'BETWEEN  AND '),
  ];

  static const _keywords = [
    FilterSuggestion(text: 'AND', kind: FilterSuggestionKind.keyword, description: 'Logical AND'),
    FilterSuggestion(text: 'OR', kind: FilterSuggestionKind.keyword, description: 'Logical OR'),
    FilterSuggestion(text: 'NOT', kind: FilterSuggestionKind.keyword, description: 'Logical NOT'),
  ];

  /// Computes suggestions based on current [text] and available [columns].
  static List<FilterSuggestion> getSuggestions({
    required String text,
    required List<String> columns,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return [
        for (final col in columns)
          FilterSuggestion(
            text: col,
            kind: FilterSuggestionKind.column,
            description: 'Column',
          ),
      ];
    }

    final tokens = trimmed.split(RegExp(r'\s+'));
    final lastToken = tokens.last;

    // Check if previous token was a column name
    if (tokens.length >= 2) {
      final prevToken = tokens[tokens.length - 2].toLowerCase();
      final isPrevCol = columns.any((c) => c.toLowerCase() == prevToken);
      if (isPrevCol) {
        final matches = _operators
            .where((op) => op.text.toLowerCase().startsWith(lastToken.toLowerCase()))
            .toList();
        if (matches.isNotEmpty) return matches;
      }
    }

    // If only one token and matches a known column exactly, suggest operators
    final exactCol = columns.firstWhere(
      (c) => c.toLowerCase() == lastToken.toLowerCase(),
      orElse: () => '',
    );
    if (exactCol.isNotEmpty) {
      return _operators;
    }

    // Partial column name match
    final matchingCols = columns
        .where((c) => c.toLowerCase().startsWith(lastToken.toLowerCase()))
        .map(
          (c) => FilterSuggestion(
            text: c,
            kind: FilterSuggestionKind.column,
            description: 'Column',
          ),
        )
        .toList();

    // Partial keyword match (AND, OR, NOT)
    final matchingKw = _keywords
        .where((k) => k.text.toLowerCase().startsWith(lastToken.toLowerCase()))
        .toList();

    return [...matchingCols, ...matchingKw];
  }
}

/// Quick Filter Bar for Data Grid.
/// Allows live client-side row filtering with context-aware autocomplete suggestions.
class DataGridFilterBar extends material.StatefulWidget {
  const DataGridFilterBar({
    super.key,
    required this.filterText,
    required this.onFilterChanged,
    required this.totalRowCount,
    required this.filteredRowCount,
    this.columns = const [],
  });

  final String filterText;
  final ValueChanged<String> onFilterChanged;
  final int totalRowCount;
  final int filteredRowCount;
  final List<String> columns;

  @override
  material.State<DataGridFilterBar> createState() => _DataGridFilterBarState();
}

class _DataGridFilterBarState extends material.State<DataGridFilterBar> {
  late final material.TextEditingController _controller;
  final _layerLink = material.LayerLink();
  material.OverlayEntry? _overlayEntry;
  List<FilterSuggestion> _suggestions = [];
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(text: widget.filterText);
  }

  @override
  void didUpdateWidget(covariant DataGridFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterText != widget.filterText &&
        _controller.text != widget.filterText) {
      _controller.text = widget.filterText;
    }
  }

  @override
  void dispose() {
    _hideSuggestions();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    widget.onFilterChanged(val);
    _updateSuggestions(val);
  }

  void _updateSuggestions(String val) {
    final suggs = FilterSuggestionEngine.getSuggestions(
      text: val,
      columns: widget.columns,
    );

    if (suggs.isEmpty || val.trim().isEmpty) {
      _hideSuggestions();
    } else {
      _suggestions = suggs;
      _highlightedIndex = 0;
      _showSuggestions();
    }
  }

  void _showSuggestions() {
    _hideSuggestions();
    final overlay = material.Overlay.maybeOf(context);
    if (overlay == null) return;

    _overlayEntry = material.OverlayEntry(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return material.Positioned(
          width: 320,
          child: material.CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const material.Offset(24, 32),
            child: material.Material(
              elevation: 4,
              borderRadius: material.BorderRadius.circular(6),
              color: isDark
                  ? const material.Color(0xFF1E1E22)
                  : const material.Color(0xFFFFFFFF),
              child: material.Container(
                decoration: material.BoxDecoration(
                  borderRadius: material.BorderRadius.circular(6),
                  border: material.Border.all(
                    color: cs.border.withValues(alpha: 0.6),
                  ),
                ),
                constraints: const material.BoxConstraints(maxHeight: 200),
                child: material.ListView.builder(
                  shrinkWrap: true,
                  padding: const material.EdgeInsets.symmetric(vertical: 4),
                  itemCount: _suggestions.length,
                  itemBuilder: (ctx, i) {
                    final s = _suggestions[i];
                    final isHighlighted = i == _highlightedIndex;
                    return material.InkWell(
                      onTap: () => _applySuggestion(s),
                      child: material.Container(
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: isHighlighted
                            ? cs.primary.withValues(alpha: 0.12)
                            : material.Colors.transparent,
                        child: material.Row(
                          children: [
                            _buildSuggestionIcon(s.kind, cs),
                            const Gap(8),
                            Text(s.text).semiBold().small(),
                            const Spacer(),
                            if (s.description.isNotEmpty)
                              Text(s.description).muted().xSmall(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  material.Widget _buildSuggestionIcon(FilterSuggestionKind kind, ColorScheme cs) {
    switch (kind) {
      case FilterSuggestionKind.column:
        return material.Icon(
          material.Icons.table_chart_outlined,
          size: 13,
          color: cs.primary,
        );
      case FilterSuggestionKind.operator:
        return material.Icon(
          material.Icons.code_rounded,
          size: 13,
          color: material.Colors.amber.shade700,
        );
      case FilterSuggestionKind.keyword:
        return material.Icon(
          material.Icons.vpn_key_outlined,
          size: 13,
          color: material.Colors.green.shade600,
        );
    }
  }

  void _hideSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _applySuggestion(FilterSuggestion s) {
    final text = _controller.text;
    final toInsert = s.insertText ?? s.text;

    final tokens = text.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty && s.kind == FilterSuggestionKind.column) {
      tokens[tokens.length - 1] = toInsert;
      final newText = '${tokens.join(' ')} ';
      _controller.value = material.TextEditingValue(
        text: newText,
        selection: material.TextSelection.collapsed(offset: newText.length),
      );
      _onChanged(newText);
    } else {
      final newText = '$text $toInsert ';
      _controller.value = material.TextEditingValue(
        text: newText,
        selection: material.TextSelection.collapsed(offset: newText.length),
      );
      _onChanged(newText);
    }
    _hideSuggestions();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFiltered = widget.filterText.trim().isNotEmpty;

    return material.CompositedTransformTarget(
      link: _layerLink,
      child: material.Container(
        height: 34,
        padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: material.BoxDecoration(
          color: cs.card,
          border: material.Border(
            bottom: material.BorderSide(
              color: cs.border.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        child: material.Row(
          children: [
            material.Icon(
              material.Icons.filter_alt_outlined,
              size: 15,
              color: isFiltered ? cs.primary : cs.mutedForeground,
            ),
            const Gap(6),
            material.Expanded(
              child: material.TextField(
                controller: _controller,
                onChanged: _onChanged,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.foreground,
                ),
                decoration: material.InputDecoration(
                  hintText: 'Filter results... (e.g. "active", "status = ACTIVE", "amount > 100")',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: cs.mutedForeground.withValues(alpha: 0.7),
                  ),
                  border: material.InputBorder.none,
                  isDense: true,
                  contentPadding: material.EdgeInsets.zero,
                ),
              ),
            ),
            if (isFiltered) ...[
              const Gap(6),
              material.Container(
                padding: const material.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: material.BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: material.BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.filteredRowCount} / ${widget.totalRowCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const Gap(4),
              material.IconButton(
                icon: const material.Icon(material.Icons.close, size: 14),
                padding: material.EdgeInsets.zero,
                constraints: const material.BoxConstraints(minWidth: 20, minHeight: 20),
                color: cs.mutedForeground,
                onPressed: () {
                  _controller.clear();
                  _hideSuggestions();
                  widget.onFilterChanged('');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
