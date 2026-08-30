import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/features/workspace/grid_groupings_engine.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Groupings / Pivot view tab for tabular data with hierarchical grouping and custom aggregations.
class DataGridGroupingsView extends material.StatefulWidget {
  const DataGridGroupingsView({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<String> columns;
  final List<List<String>> rows;

  @override
  material.State<DataGridGroupingsView> createState() =>
      _DataGridGroupingsViewState();
}

class _DataGridGroupingsViewState
    extends material.State<DataGridGroupingsView> {
  late List<int> _selectedColIndices;
  GroupingAggType _aggType = GroupingAggType.count;
  int? _aggTargetColIndex;
  GroupSortBy _sortBy = GroupSortBy.count;
  bool _sortAscending = false;
  final Set<String> _expandedKeys = {};

  @override
  void initState() {
    super.initState();
    _selectedColIndices = widget.columns.isNotEmpty ? [0] : [];
    if (widget.columns.length > 1) {
      // Pick first numeric-looking column as default target for sum/avg if available
      _aggTargetColIndex = 1;
    }
  }

  @override
  void didUpdateWidget(covariant DataGridGroupingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns) {
      if (_selectedColIndices.isEmpty && widget.columns.isNotEmpty) {
        _selectedColIndices = [0];
      } else {
        _selectedColIndices.removeWhere((idx) => idx >= widget.columns.length);
        if (_selectedColIndices.isEmpty && widget.columns.isNotEmpty) {
          _selectedColIndices = [0];
        }
      }
    }
  }

  void _exportPivot() {
    final groups = GridGroupingsEngine.buildGroups(
      groupColIndices: _selectedColIndices,
      rows: widget.rows,
      aggConfig: GroupAggregationConfig(
        aggType: _aggType,
        targetColIndex: _aggTargetColIndex,
      ),
      sortBy: _sortBy,
      sortAscending: _sortAscending,
    );

    final groupName = _selectedColIndices.isNotEmpty
        ? widget.columns[_selectedColIndices.first]
        : 'Group';
    final csv = GridGroupingsEngine.exportPivotToCsv(
      groups: groups,
      groupByColumnName: groupName,
      aggConfig: GroupAggregationConfig(
        aggType: _aggType,
        targetColIndex: _aggTargetColIndex,
      ),
    );

    Clipboard.setData(ClipboardData(text: csv));
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (widget.columns.isEmpty || widget.rows.isEmpty) {
      return material.Center(
        child: const Text('No data available for grouping.').muted(),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final groups = GridGroupingsEngine.buildGroups(
      groupColIndices: _selectedColIndices,
      rows: widget.rows,
      aggConfig: GroupAggregationConfig(
        aggType: _aggType,
        targetColIndex: _aggTargetColIndex,
      ),
      sortBy: _sortBy,
      sortAscending: _sortAscending,
    );

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Top Toolbar for selecting Group By, Aggregation, and Sorting
        material.Container(
          height: 40,
          padding: const material.EdgeInsets.symmetric(horizontal: 10),
          decoration: material.BoxDecoration(
            color: cs.card,
            border: material.Border(
              bottom: material.BorderSide(
                color: cs.border.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
          child: material.SingleChildScrollView(
            scrollDirection: material.Axis.horizontal,
            child: material.Row(
              children: [
                material.Icon(
                  material.Icons.account_tree_outlined,
                  size: 15,
                  color: cs.primary,
                ),
                const Gap(6),
                const Text('Group:').small().semiBold(),
                const Gap(6),
                material.DropdownButton<int>(
                  value: _selectedColIndices.isNotEmpty &&
                          _selectedColIndices.first < widget.columns.length
                      ? _selectedColIndices.first
                      : 0,
                  isDense: true,
                  underline: const material.SizedBox.shrink(),
                  style: TextStyle(fontSize: 12, color: cs.foreground),
                  items: List.generate(widget.columns.length, (i) {
                    return material.DropdownMenuItem<int>(
                      value: i,
                      child: Text(widget.columns[i]),
                    );
                  }),
                  onChanged: (idx) {
                    if (idx != null) {
                      setState(() {
                        _selectedColIndices = [idx];
                        _expandedKeys.clear();
                      });
                    }
                  },
                ),

                const Gap(12),
                material.VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: cs.border.withValues(alpha: 0.3),
                ),
                const Gap(12),

                // Aggregation Selector
                const Text('Agg:').small().semiBold(),
                const Gap(6),
                material.DropdownButton<GroupingAggType>(
                  value: _aggType,
                  isDense: true,
                  underline: const material.SizedBox.shrink(),
                  style: TextStyle(fontSize: 12, color: cs.foreground),
                  items: GroupingAggType.values.map((t) {
                    return material.DropdownMenuItem<GroupingAggType>(
                      value: t,
                      child: Text(t.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _aggType = val);
                    }
                  },
                ),
                if (_aggType != GroupingAggType.count) ...[
                  const Gap(4),
                  material.DropdownButton<int>(
                    value: _aggTargetColIndex != null &&
                            _aggTargetColIndex! < widget.columns.length
                        ? _aggTargetColIndex
                        : 0,
                    isDense: true,
                    underline: const material.SizedBox.shrink(),
                    style: TextStyle(fontSize: 12, color: cs.foreground),
                    items: List.generate(widget.columns.length, (i) {
                      return material.DropdownMenuItem<int>(
                        value: i,
                        child: Text(widget.columns[i]),
                      );
                    }),
                    onChanged: (idx) {
                      if (idx != null) {
                        setState(() => _aggTargetColIndex = idx);
                      }
                    },
                  ),
                ],

                const Gap(12),
                material.VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: cs.border.withValues(alpha: 0.3),
                ),
                const Gap(12),

                // Sort Selector
                const Text('Sort:').small().semiBold(),
                const Gap(6),
                material.DropdownButton<GroupSortBy>(
                  value: _sortBy,
                  isDense: true,
                  underline: const material.SizedBox.shrink(),
                  style: TextStyle(fontSize: 12, color: cs.foreground),
                  items: GroupSortBy.values.map((s) {
                    return material.DropdownMenuItem<GroupSortBy>(
                      value: s,
                      child: Text(s.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _sortBy = val);
                    }
                  },
                ),
                material.IconButton(
                  icon: material.Icon(
                    _sortAscending
                        ? material.Icons.arrow_upward_rounded
                        : material.Icons.arrow_downward_rounded,
                    size: 14,
                  ),
                  padding: material.EdgeInsets.zero,
                  constraints: const material.BoxConstraints(minWidth: 24, minHeight: 24),
                  color: cs.mutedForeground,
                  onPressed: () => setState(() => _sortAscending = !_sortAscending),
                ),

                const Gap(8),
                material.Tooltip(
                  message: 'Copy Pivot CSV to Clipboard',
                  child: material.IconButton(
                    icon: const material.Icon(material.Icons.copy_rounded, size: 14),
                    padding: material.EdgeInsets.zero,
                    constraints: const material.BoxConstraints(minWidth: 24, minHeight: 24),
                    color: cs.mutedForeground,
                    onPressed: _exportPivot,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Groupings List
        material.Expanded(
          child: material.ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) => material.Divider(
              height: 1,
              color: cs.border.withValues(alpha: 0.2),
            ),
            itemBuilder: (context, idx) {
              final group = groups[idx];
              final isExpanded = _expandedKeys.contains(group.groupKey);

              return material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedKeys.remove(group.groupKey);
                        } else {
                          _expandedKeys.add(group.groupKey);
                        }
                      });
                    },
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: material.Row(
                        children: [
                          material.Icon(
                            isExpanded
                                ? material.Icons.keyboard_arrow_down_rounded
                                : material.Icons.keyboard_arrow_right_rounded,
                            size: 18,
                            color: cs.mutedForeground,
                          ),
                          const Gap(8),
                          material.Expanded(
                            child: Text(
                              group.groupKey,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          if (group.aggValue != null && _aggType != GroupingAggType.count) ...[
                            material.Container(
                              padding: const material.EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const material.EdgeInsets.only(right: 6),
                              decoration: material.BoxDecoration(
                                color: cs.secondary.withValues(alpha: 0.3),
                                borderRadius: material.BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_aggType.label}: ${group.aggValue!.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.foreground,
                                ),
                              ),
                            ),
                          ],
                          material.Container(
                            padding: const material.EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: material.BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: material.BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${group.count} rows (${group.percentage.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Expanded sub-grid
                  if (isExpanded)
                    material.Container(
                      height: 220,
                      margin: const material.EdgeInsets.only(
                        left: 28,
                        right: 12,
                        bottom: 8,
                      ),
                      decoration: material.BoxDecoration(
                        border: material.Border.all(
                          color: cs.border.withValues(alpha: 0.4),
                        ),
                        borderRadius: material.BorderRadius.circular(6),
                      ),
                      child: VirtualResultGrid(
                        columns: widget.columns,
                        rows: group.rows,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
