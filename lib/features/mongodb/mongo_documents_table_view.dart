import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Precomputed column and cell model for [MongoDocumentsTableView].
class MongoTableGridData {
  const MongoTableGridData({
    required this.columns,
    required this.rows,
    required this.columnDataTypes,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final Map<String, String> columnDataTypes;

  factory MongoTableGridData.fromDocuments(List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return const MongoTableGridData(
        columns: [],
        rows: [],
        columnDataTypes: {},
      );
    }

    final columnSet = <String>{};
    for (final doc in documents) {
      columnSet.addAll(doc.keys);
    }

    final columns = <String>[];
    if (columnSet.remove('_id')) {
      columns.add('_id');
    }
    final otherCols = columnSet.toList()..sort();
    columns.addAll(otherCols);

    final columnDataTypes = <String, String>{};
    for (final col in columns) {
      for (final doc in documents) {
        final val = doc[col];
        if (val != null) {
          columnDataTypes[col] = _inferType(val);
          break;
        }
      }
    }

    final rows = <List<String>>[];
    for (final doc in documents) {
      final row = <String>[];
      for (final col in columns) {
        if (!doc.containsKey(col)) {
          row.add('');
        } else {
          final val = doc[col];
          row.add(_formatCell(val));
        }
      }
      rows.add(row);
    }

    return MongoTableGridData(
      columns: columns,
      rows: rows,
      columnDataTypes: columnDataTypes,
    );
  }

  static String _inferType(Object val) {
    if (val is ObjectId) return 'ObjectId';
    if (val is Map) return 'Object';
    if (val is List) return 'Array';
    if (val is int) return 'Int32';
    if (val is double) return 'Double';
    if (val is bool) return 'Boolean';
    if (val is DateTime) return 'Date';
    if (val is String) return 'String';
    return val.runtimeType.toString();
  }

  static String _formatCell(Object? val) {
    if (val == null) return 'NULL';
    if (val is ObjectId) return val.oid;
    if (val is DateTime) return val.toUtc().toIso8601String();
    if (val is Map) {
      final n = val.length;
      return '{ $n ${n == 1 ? "field" : "fields"} }';
    }
    if (val is List) {
      final n = val.length;
      return '[ $n ${n == 1 ? "item" : "items"} ]';
    }
    if (val is String) return val;
    return val.toString();
  }
}

/// Table Grid view for MongoDB documents using [VirtualResultGrid].
class MongoDocumentsTableView extends StatefulWidget {
  const MongoDocumentsTableView({
    super.key,
    required this.documents,
    this.onDocumentTap,
    this.onDeleteDocument,
    this.onInspectField,
  });

  final List<Map<String, dynamic>> documents;
  final ValueChanged<Map<String, dynamic>>? onDocumentTap;
  final ValueChanged<Map<String, dynamic>>? onDeleteDocument;
  final void Function(Map<String, dynamic> doc, String field)? onInspectField;

  @override
  State<MongoDocumentsTableView> createState() =>
      _MongoDocumentsTableViewState();
}

class _MongoDocumentsTableViewState extends State<MongoDocumentsTableView> {
  late MongoTableGridData _gridData;
  int? _selectedDocIndex;

  @override
  void initState() {
    super.initState();
    _gridData = MongoTableGridData.fromDocuments(widget.documents);
  }

  @override
  void didUpdateWidget(covariant MongoDocumentsTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.documents, widget.documents)) {
      _gridData = MongoTableGridData.fromDocuments(widget.documents);
      if (_selectedDocIndex != null &&
          _selectedDocIndex! >= widget.documents.length) {
        _selectedDocIndex = null;
      }
    }
  }

  Future<void> _copySelectedDocJson(Map<String, dynamic> doc) async {
    final ejson = mongoDocumentToEjson(doc);
    await Clipboard.setData(ClipboardData(text: ejson));
    if (mounted) {
      showAppToast(
        context: context,
        message: 'Document JSON copied to clipboard',
        variant: AppToastVariant.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.documents.isEmpty || _gridData.columns.isEmpty) {
      return material.Center(
        child: const Text('No documents found').muted(),
      );
    }

    final selectedDoc = (_selectedDocIndex != null &&
            _selectedDocIndex! >= 0 &&
            _selectedDocIndex! < widget.documents.length)
        ? widget.documents[_selectedDocIndex!]
        : null;

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Action / Status bar for selected row
        material.Container(
          height: 36,
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
              if (selectedDoc != null) ...[
                material.Icon(
                  material.Icons.check_circle_outline_rounded,
                  size: 14,
                  color: cs.primary,
                ),
                const Gap(6),
                Text('Row ${_selectedDocIndex! + 1} selected').small(),
                if (selectedDoc['_id'] != null) ...[
                  const Gap(8),
                  Text('(${selectedDoc['_id']})').muted().small(),
                ],
                const Spacer(),
                if (widget.onDocumentTap != null) ...[
                  OutlineButton(
                    onPressed: () => widget.onDocumentTap!(selectedDoc),
                    size: ButtonSize.small,
                    leading: const material.Icon(
                      material.Icons.open_in_new_rounded,
                      size: 13,
                    ),
                    child: const Text('View Document'),
                  ),
                  const Gap(6),
                ],
                OutlineButton(
                  onPressed: () => _copySelectedDocJson(selectedDoc),
                  size: ButtonSize.small,
                  leading: const material.Icon(
                    material.Icons.copy_rounded,
                    size: 13,
                  ),
                  child: const Text('Copy JSON'),
                ),
                if (widget.onDeleteDocument != null) ...[
                  const Gap(6),
                  DestructiveButton(
                    onPressed: () => widget.onDeleteDocument!(selectedDoc),
                    size: ButtonSize.small,
                    leading: const material.Icon(
                      material.Icons.delete_outline_rounded,
                      size: 13,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ] else ...[
                Text('${widget.documents.length} rows · Click a row to select · Click column header to sort')
                    .muted()
                    .small(),
              ],
            ],
          ),
        ),
        // Grid
        material.Expanded(
          child: VirtualResultGrid(
            columns: _gridData.columns,
            rows: _gridData.rows,
            columnDataTypes: _gridData.columnDataTypes,
            onRowSelected: (rowIndex) {
              setState(() {
                _selectedDocIndex = rowIndex;
              });
            },
          ),
        ),
      ],
    );
  }
}
