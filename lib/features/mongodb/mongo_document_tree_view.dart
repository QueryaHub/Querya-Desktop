import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
import 'package:querya_desktop/features/mongodb/mongo_field_codec.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Appends a key or list index to a JavaScript / JSON Path expression.
///
/// Examples:
/// - parent = '', key = 'address' => 'address'
/// - parent = 'address', key = 'geo' => 'address.geo'
/// - parent = 'address.geo', index = 0 => 'address.geo[0]'
/// - parent = 'address.geo[0]', key = 'lat' => 'address.geo[0].lat'
String appendJsonPath(String parentPath, Object keyOrIndex) {
  if (keyOrIndex is int) {
    return '$parentPath[$keyOrIndex]';
  }
  final keyStr = keyOrIndex.toString();
  if (parentPath.isEmpty) {
    return keyStr;
  }
  if (RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$').hasMatch(keyStr)) {
    return '$parentPath.$keyStr';
  }
  final escaped = keyStr.replaceAll('"', r'\"');
  return '$parentPath["$escaped"]';
}

/// Interactive folding tree view for MongoDB documents.
class MongoDocumentTreeView extends StatefulWidget {
  const MongoDocumentTreeView({
    super.key,
    required this.documents,
    this.startIndex = 0,
    this.onDocumentTap,
    this.onDeleteDocument,
    this.onInspectField,
  });

  final List<Map<String, dynamic>> documents;
  final int startIndex;
  final ValueChanged<Map<String, dynamic>>? onDocumentTap;
  final ValueChanged<Map<String, dynamic>>? onDeleteDocument;
  final void Function(Map<String, dynamic> doc, String field)? onInspectField;

  @override
  State<MongoDocumentTreeView> createState() => _MongoDocumentTreeViewState();
}

class _MongoDocumentTreeViewState extends State<MongoDocumentTreeView> {
  final Set<String> _expandedNodeIds = {};
  final material.TextEditingController _searchController =
      material.TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Default to expanding all root document nodes
    for (var i = 0; i < widget.documents.length; i++) {
      _expandedNodeIds.add('doc_$i');
    }
  }

  @override
  void didUpdateWidget(covariant MongoDocumentTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.documents, widget.documents)) {
      for (var i = 0; i < widget.documents.length; i++) {
        _expandedNodeIds.add('doc_$i');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleNode(String nodeId) {
    setState(() {
      if (_expandedNodeIds.contains(nodeId)) {
        _expandedNodeIds.remove(nodeId);
      } else {
        _expandedNodeIds.add(nodeId);
      }
    });
  }

  void _expandAll() {
    final allIds = <String>{};
    for (var i = 0; i < widget.documents.length; i++) {
      allIds.add('doc_$i');
      _collectContainerIds(widget.documents[i], 'doc_$i', '', allIds);
    }
    setState(() {
      _expandedNodeIds.addAll(allIds);
    });
  }

  void _collectContainerIds(
    Object? value,
    String prefix,
    String parentPath,
    Set<String> out,
  ) {
    if (value is Map) {
      for (final entry in value.entries) {
        final currentPath = appendJsonPath(parentPath, entry.key);
        if (entry.value is Map || entry.value is List) {
          out.add('${prefix}_$currentPath');
          _collectContainerIds(entry.value, prefix, currentPath, out);
        }
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final currentPath = appendJsonPath(parentPath, i);
        if (value[i] is Map || value[i] is List) {
          out.add('${prefix}_$currentPath');
          _collectContainerIds(value[i], prefix, currentPath, out);
        }
      }
    }
  }

  void _collapseAll() {
    setState(() {
      _expandedNodeIds.clear();
    });
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showAppToast(
        context: context,
        message: '$label copied to clipboard',
        variant: AppToastVariant.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.documents.isEmpty) {
      return material.Center(
        child: const Text('No documents found').muted(),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Tree Toolbar
        material.Container(
          height: 40,
          padding: const material.EdgeInsets.symmetric(horizontal: 16),
          decoration: material.BoxDecoration(
            color: cs.muted.withValues(alpha: 0.1),
            border: material.Border(
              bottom: material.BorderSide(
                color: cs.border.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              // Search input
              material.SizedBox(
                width: 200,
                height: 28,
                child: TextField(
                  controller: _searchController,
                  placeholder: const Text('Filter keys / values...'),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                ),
              ),
              const Gap(8),
              if (_searchQuery.isNotEmpty)
                GhostButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  size: ButtonSize.small,
                  child: const material.Icon(
                    material.Icons.close_rounded,
                    size: 14,
                  ),
                ),
              const Spacer(),
              OutlineButton(
                onPressed: _expandAll,
                size: ButtonSize.small,
                leading: const material.Icon(
                  material.Icons.unfold_more_rounded,
                  size: 14,
                ),
                child: const Text('Expand All'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: _collapseAll,
                size: ButtonSize.small,
                leading: const material.Icon(
                  material.Icons.unfold_less_rounded,
                  size: 14,
                ),
                child: const Text('Collapse All'),
              ),
            ],
          ),
        ),
        // Virtualized Document Tree List
        material.Expanded(
          child: material.ListView.builder(
            padding: const material.EdgeInsets.all(12),
            itemCount: widget.documents.length,
            itemBuilder: (context, i) {
              return _buildDocumentNode(i, widget.documents[i], cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentNode(
    int docIndex,
    Map<String, dynamic> doc,
    ColorScheme cs,
  ) {
    final docNodeId = 'doc_$docIndex';
    final isExpanded = _expandedNodeIds.contains(docNodeId);
    final idVal = doc['_id'];
    final idString = idVal is ObjectId ? idVal.oid : idVal?.toString() ?? 'none';
    final fieldsCount = doc.keys.length;

    return material.Container(
      margin: const material.EdgeInsets.only(bottom: 8),
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(6),
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.35),
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Document Header
          material.InkWell(
            onTap: () => _toggleNode(docNodeId),
            borderRadius: material.BorderRadius.circular(6),
            child: material.Padding(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: Row(
                children: [
                  material.Icon(
                    isExpanded
                        ? material.Icons.expand_more_rounded
                        : material.Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.mutedForeground,
                  ),
                  const Gap(6),
                  material.Icon(
                    material.Icons.description_outlined,
                    size: 16,
                    color: cs.primary,
                  ),
                  const Gap(8),
                  Text(
                    '#${widget.startIndex + docIndex + 1}',
                    style: const material.TextStyle(
                      fontWeight: material.FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Gap(8),
                  material.Container(
                    padding: const material.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: material.BoxDecoration(
                      color: cs.muted.withValues(alpha: 0.25),
                      borderRadius: material.BorderRadius.circular(4),
                    ),
                    child: Text(
                      '_id: $idString',
                      style: material.TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: cs.mutedForeground,
                      ),
                    ),
                  ),
                  const Gap(8),
                  Text('$fieldsCount fields').muted().small(),
                  const Spacer(),
                  // Actions
                  _TreeIconButton(
                    icon: material.Icons.copy_rounded,
                    tooltip: 'Copy Document JSON',
                    onTap: () => _copyText(
                      mongoDocumentToEjson(doc),
                      'Document JSON',
                    ),
                  ),
                  if (widget.onDocumentTap != null) ...[
                    const Gap(4),
                    _TreeIconButton(
                      icon: material.Icons.open_in_new_rounded,
                      tooltip: 'View / Edit Document',
                      onTap: () => widget.onDocumentTap!(doc),
                    ),
                  ],
                  if (widget.onDeleteDocument != null) ...[
                    const Gap(4),
                    _TreeIconButton(
                      icon: material.Icons.delete_outline_rounded,
                      tooltip: 'Delete Document',
                      color: cs.destructive,
                      onTap: () => widget.onDeleteDocument!(doc),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded Tree content
          if (isExpanded) ...[
            material.Divider(
              height: 1,
              color: cs.border.withValues(alpha: 0.2),
            ),
            material.Padding(
              padding: const material.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 8,
              ),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: doc.entries.map((entry) {
                  return _buildSubtree(
                    docIndex: docIndex,
                    rootDoc: doc,
                    parentPath: '',
                    keyOrIndex: entry.key,
                    value: entry.value,
                    depth: 1,
                    cs: cs,
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtree({
    required int docIndex,
    required Map<String, dynamic> rootDoc,
    required String parentPath,
    required Object keyOrIndex,
    required Object? value,
    required int depth,
    required ColorScheme cs,
  }) {
    final currentPath = appendJsonPath(parentPath, keyOrIndex);
    final nodeId = 'doc_${docIndex}_$currentPath';

    if (value is Map) {
      final isExpanded = _expandedNodeIds.contains(nodeId);
      final count = value.length;
      final keyLabel = keyOrIndex.toString();

      // Check search match
      final matchesSearch = _searchQuery.isEmpty ||
          keyLabel.toLowerCase().contains(_searchQuery) ||
          currentPath.toLowerCase().contains(_searchQuery);

      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _buildContainerRow(
            depth: depth,
            keyLabel: keyLabel,
            badgeLabel: '{ $count ${count == 1 ? "field" : "fields"} }',
            isExpanded: isExpanded,
            jsonPath: currentPath,
            rawSubtree: value,
            cs: cs,
            onToggle: () => _toggleNode(nodeId),
            matchesSearch: matchesSearch,
          ),
          if (isExpanded)
            material.Padding(
              padding: const material.EdgeInsets.only(left: 12),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: value.entries.map((e) {
                  return _buildSubtree(
                    docIndex: docIndex,
                    rootDoc: rootDoc,
                    parentPath: currentPath,
                    keyOrIndex: e.key,
                    value: e.value,
                    depth: depth + 1,
                    cs: cs,
                  );
                }).toList(),
              ),
            ),
        ],
      );
    }

    if (value is List) {
      final isExpanded = _expandedNodeIds.contains(nodeId);
      final count = value.length;
      final keyLabel = keyOrIndex.toString();

      final matchesSearch = _searchQuery.isEmpty ||
          keyLabel.toLowerCase().contains(_searchQuery) ||
          currentPath.toLowerCase().contains(_searchQuery);

      return material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _buildContainerRow(
            depth: depth,
            keyLabel: keyLabel,
            badgeLabel: '[ $count ${count == 1 ? "item" : "items"} ]',
            isExpanded: isExpanded,
            jsonPath: currentPath,
            rawSubtree: value,
            cs: cs,
            onToggle: () => _toggleNode(nodeId),
            matchesSearch: matchesSearch,
          ),
          if (isExpanded)
            material.Padding(
              padding: const material.EdgeInsets.only(left: 12),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < value.length; i++)
                    _buildSubtree(
                      docIndex: docIndex,
                      rootDoc: rootDoc,
                      parentPath: currentPath,
                      keyOrIndex: i,
                      value: value[i],
                      depth: depth + 1,
                      cs: cs,
                    ),
                ],
              ),
            ),
        ],
      );
    }

    // Leaf node
    return _buildLeafRow(
      depth: depth,
      keyOrIndex: keyOrIndex,
      value: value,
      jsonPath: currentPath,
      rootDoc: rootDoc,
      cs: cs,
    );
  }

  Widget _buildContainerRow({
    required int depth,
    required String keyLabel,
    required String badgeLabel,
    required bool isExpanded,
    required String jsonPath,
    required Object rawSubtree,
    required ColorScheme cs,
    required VoidCallback onToggle,
    required bool matchesSearch,
  }) {
    return material.Container(
      height: 28,
      padding: material.EdgeInsets.only(left: depth * 14.0),
      child: Row(
        children: [
          material.InkWell(
            onTap: onToggle,
            borderRadius: material.BorderRadius.circular(4),
            child: material.Padding(
              padding: const material.EdgeInsets.all(2),
              child: material.Icon(
                isExpanded
                    ? material.Icons.expand_more_rounded
                    : material.Icons.chevron_right_rounded,
                size: 16,
                color: cs.mutedForeground,
              ),
            ),
          ),
          const Gap(4),
          Text(
            keyLabel,
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: material.FontWeight.w600,
              color: matchesSearch && _searchQuery.isNotEmpty
                  ? cs.primary
                  : cs.foreground,
            ),
          ),
          const Gap(6),
          Text(
            badgeLabel,
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: cs.mutedForeground,
            ),
          ),
          const Spacer(),
          _TreeIconButton(
            icon: material.Icons.alt_route_rounded,
            tooltip: 'Copy JSON Path ($jsonPath)',
            onTap: () => _copyText(jsonPath, 'JSON Path: $jsonPath'),
          ),
          const Gap(4),
          _TreeIconButton(
            icon: material.Icons.copy_rounded,
            tooltip: 'Copy JSON',
            onTap: () {
              try {
                final encoded = const JsonEncoder.withIndent('  ')
                    .convert(rawSubtree);
                _copyText(encoded, 'JSON');
              } catch (_) {
                _copyText(rawSubtree.toString(), 'Value');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLeafRow({
    required int depth,
    required Object keyOrIndex,
    required Object? value,
    required String jsonPath,
    required Map<String, dynamic> rootDoc,
    required ColorScheme cs,
  }) {
    final keyLabel = keyOrIndex is int ? '[$keyOrIndex]' : keyOrIndex.toString();
    final valueDisplay = _formatLeafDisplay(value);
    final valueColor = _leafValueColor(value, cs);
    final typeName = _leafTypeName(value);

    final isMatch = _searchQuery.isNotEmpty &&
        (keyLabel.toLowerCase().contains(_searchQuery) ||
            valueDisplay.toLowerCase().contains(_searchQuery) ||
            jsonPath.toLowerCase().contains(_searchQuery));

    final canEdit = depth == 1 &&
        keyOrIndex is String &&
        widget.onInspectField != null &&
        !mongoFieldIsReadOnly(keyOrIndex);

    return material.Container(
      height: 28,
      padding: material.EdgeInsets.only(left: depth * 14.0 + 16.0),
      child: Row(
        children: [
          Text(
            keyLabel,
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: material.FontWeight.w500,
              color: isMatch ? cs.primary : cs.foreground,
            ),
          ),
          Text(
            ': ',
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: cs.mutedForeground,
            ),
          ),
          material.Expanded(
            child: Text(
              valueDisplay,
              overflow: TextOverflow.ellipsis,
              style: material.TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontStyle:
                    value == null ? material.FontStyle.italic : material.FontStyle.normal,
                color: valueColor,
              ),
            ),
          ),
          const Gap(6),
          // Type badge
          material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 1,
            ),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.15),
              borderRadius: material.BorderRadius.circular(3),
            ),
            child: Text(
              typeName,
              style: material.TextStyle(
                fontSize: 10,
                color: cs.mutedForeground,
              ),
            ),
          ),
          const Gap(6),
          _TreeIconButton(
            icon: material.Icons.alt_route_rounded,
            tooltip: 'Copy JSON Path ($jsonPath)',
            onTap: () => _copyText(jsonPath, 'JSON Path: $jsonPath'),
          ),
          const Gap(4),
          _TreeIconButton(
            icon: material.Icons.copy_rounded,
            tooltip: 'Copy Value',
            onTap: () => _copyText(valueDisplay, 'Value'),
          ),
          if (canEdit) ...[
            const Gap(4),
            _TreeIconButton(
              icon: material.Icons.edit_note_rounded,
              tooltip: 'Edit Field',
              onTap: () => widget.onInspectField!(rootDoc, keyOrIndex),
            ),
          ],
        ],
      ),
    );
  }

  String _formatLeafDisplay(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is ObjectId) return 'ObjectId("${value.oid}")';
    if (value is DateTime) return 'ISODate("${value.toUtc().toIso8601String()}")';
    return value.toString();
  }

  Color _leafValueColor(Object? value, ColorScheme cs) {
    if (value == null) return cs.mutedForeground;
    if (value is String) return const Color(0xFF22C55E); // Green
    if (value is num) return const Color(0xFF3B82F6); // Blue
    if (value is bool) return const Color(0xFFF97316); // Orange
    if (value is ObjectId) return cs.primary; // Primary / Purple
    if (value is DateTime) return const Color(0xFF06B6D4); // Cyan
    return cs.foreground;
  }

  String _leafTypeName(Object? value) {
    if (value == null) return 'null';
    if (value is String) return 'str';
    if (value is int) return 'int';
    if (value is double) return 'dbl';
    if (value is bool) return 'bool';
    if (value is ObjectId) return 'oid';
    if (value is DateTime) return 'date';
    return value.runtimeType.toString();
  }
}

class _TreeIconButton extends StatelessWidget {
  const _TreeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final material.IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Tooltip(
      message: tooltip,
      child: material.InkWell(
        onTap: onTap,
        borderRadius: material.BorderRadius.circular(4),
        child: material.Padding(
          padding: const material.EdgeInsets.all(3),
          child: material.Icon(
            icon,
            size: 14,
            color: color ?? cs.mutedForeground,
          ),
        ),
      ),
    );
  }
}
