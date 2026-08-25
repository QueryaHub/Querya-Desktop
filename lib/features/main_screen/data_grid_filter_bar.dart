import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Quick Filter Bar for Data Grid.
/// Allows live client-side row filtering without re-running SQL queries.
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
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFiltered = widget.filterText.trim().isNotEmpty;

    return material.Container(
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
              onChanged: widget.onFilterChanged,
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
                widget.onFilterChanged('');
              },
            ),
          ],
        ],
      ),
    );
  }
}
