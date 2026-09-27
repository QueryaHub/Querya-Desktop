import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_add_document_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongo_ejson.dart';
import 'package:querya_desktop/features/mongodb/mongo_field_codec.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/features/workspace/grid_cell_popover_inspector.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

const _defaultLimit = 25;

/// Paginated document browser for a MongoDB collection.
class MongoDocumentsView extends material.StatefulWidget {
  const MongoDocumentsView({
    super.key,
    required this.connection,
    required this.database,
    required this.collection,
    this.onDocumentTap,
    this.refreshToken = 0,
  });

  final MongoConnection connection;
  final String database;
  final String collection;
  final ValueChanged<Map<String, dynamic>>? onDocumentTap;

  /// Incremented by the parent when the user requests a refresh (toolbar).
  final int refreshToken;

  @override
  material.State<MongoDocumentsView> createState() =>
      _MongoDocumentsViewState();
}

/// Total document count implied by one page alone, or null when it is unknown.
///
/// A short non-empty page (or an empty first page) ends the result set, so the
/// total is `skip + pageLength` without a separate count round trip.
int? mongoExactTotalFromPage({
  required int skip,
  required int limit,
  required int pageLength,
}) {
  if (pageLength >= limit) return null;
  if (pageLength == 0 && skip > 0) return null;
  return skip + pageLength;
}

/// Whether a next page may exist: from the [total] when known, otherwise
/// whenever the current page is full.
bool mongoHasNextPage({
  required int skip,
  required int limit,
  required int pageLength,
  int? total,
}) {
  if (total != null) return skip + limit < total;
  return pageLength >= limit;
}

class _MongoDocumentsViewState extends material.State<MongoDocumentsView> {
  List<Map<String, dynamic>> _documents = [];
  /// Exact match count, or null while the background count is still running
  /// (the first page is painted from `find` alone).
  int? _totalCount;

  /// Bumped per load so a slow older find / count cannot overwrite a newer one.
  int _loadSeq = 0;
  int _skip = 0;
  final int _limit = _defaultLimit;
  bool _loading = true;
  String? _error;

  final _filterController = material.TextEditingController();
  Map<String, dynamic>? _activeFilter;
  String? _emptyFilterHint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MongoDocumentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// Loads the current page. Page navigation passes [keepTotal] so the known
  /// total is reused instead of recounting on every page.
  Future<void> _load({bool keepTotal = false}) async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    final knownTotal = keepTotal ? _totalCount : null;
    setState(() {
      _loading = true;
      _error = null;
      _totalCount = knownTotal;
    });
    try {
      final docs = await MongoService.instance.find(
        widget.connection,
        widget.database,
        widget.collection,
        filter: _activeFilter,
        limit: _limit,
        skip: _skip,
      );
      if (!mounted || seq != _loadSeq) return;
      // A short, non-empty page (or an empty first page) pins the total
      // without a count round trip.
      final exactTotal = knownTotal ??
          mongoExactTotalFromPage(
            skip: _skip,
            limit: _limit,
            pageLength: docs.length,
          );
      setState(() {
        _totalCount = exactTotal;
        _documents = docs;
        _loading = false;
        _emptyFilterHint = docs.isEmpty &&
                _activeFilter != null &&
                mongoFilterNeedsObjectIdHint(_activeFilter!)
            ? kMongoFilterIdStringHint
            : null;
      });
      if (exactTotal == null) unawaited(_loadCount(seq));
    } catch (e) {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Exact count after the first page is on screen. Failures leave the total
  /// unknown ("N+ documents") instead of failing the list.
  Future<void> _loadCount(int seq) async {
    try {
      final count = await MongoService.instance.countDocuments(
        widget.connection,
        widget.database,
        widget.collection,
        filter: _activeFilter,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() => _totalCount = count);
    } catch (_) {
      // Keep the "maybe more" pagination.
    }
  }

  /// True when a next page may exist: known total, else "page is full".
  bool get _hasNextPage {
    return mongoHasNextPage(
      skip: _skip,
      limit: _limit,
      pageLength: _documents.length,
      total: _totalCount,
    );
  }

  void _applyFilter() {
    final text = _filterController.text.trim();
    if (text.isEmpty) {
      _activeFilter = null;
    } else {
      try {
        _activeFilter = mongoFilterFromJson(text);
      } catch (e) {
        setState(() {
          _error = 'Invalid JSON filter: $e';
        });
        return;
      }
    }
    _emptyFilterHint = null;
    _skip = 0;
    _load();
  }

  void _clearFilter() {
    _filterController.clear();
    _activeFilter = null;
    _emptyFilterHint = null;
    _skip = 0;
    _load();
  }

  void _goNextPage() {
    if (_hasNextPage) {
      _skip += _limit;
      _load(keepTotal: true);
    }
  }

  void _goPrevPage() {
    if (_skip > 0) {
      _skip = (_skip - _limit).clamp(0, _skip);
      _load(keepTotal: true);
    }
  }

  Future<void> _addDocument() async {
    final doc = await showMongoAddDocumentDialog(
      context,
      database: widget.database,
      collection: widget.collection,
    );
    if (doc == null) return;

    try {
      await MongoService.instance.insertDocument(
        widget.connection,
        widget.database,
        widget.collection,
        doc,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to insert: $e';
        });
      }
    }
  }

  Future<void> _inspectField(Map<String, dynamic> doc, String field) async {
    if (mongoFieldIsReadOnly(field)) return;
    final id = doc['_id'];
    if (id == null) return;
    await showGridCellInspectorDialog(
      context: context,
      columnName: field,
      initialValue: mongoFieldToDisplay(doc[field]),
      dataTypeName: doc[field]?.runtimeType.toString() ?? 'MongoDB field',
      onSaveToDatabase: (value) async {
        mongoAssertFieldEditable(field);
        await MongoService.instance.updateDocument(
          widget.connection,
          widget.database,
          widget.collection,
          {'_id': id},
          {
            r'$set': {
              field: mongoDisplayToValue(value, original: doc[field]),
            }
          },
        );
        if (!mounted) return;
        await _load();
      },
    );
  }

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final id = doc['_id'];
    if (id == null) return;

    final confirmed = await confirmDestructiveMongoAction(
      context: context,
      type: DestructiveSqlType.deleteDocument,
      targetName: id.toString(),
      commandPreview:
          'db.${widget.collection}.deleteOne({ _id: ${id.toString()} })',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;

    try {
      await MongoService.instance.deleteDocument(
        widget.connection,
        widget.database,
        widget.collection,
        {'_id': id},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to delete: $e';
        });
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading && _documents.isEmpty) {
      return material.Center(
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 32,
              height: 32,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(16),
            const Text('Loading documents...').muted().small(),
          ],
        ),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Filter bar
        _buildFilterBar(cs),
        const Divider(height: 1),
        // Error banner
        if (_error != null) _buildErrorBanner(cs),
        // Document list (virtualized)
        material.Expanded(
          child: _documents.isEmpty
              ? material.Center(
                  child: material.Padding(
                    padding: const material.EdgeInsets.all(48),
                    child: Text(_emptyFilterHint ?? 'No documents found')
                        .muted(),
                  ),
                )
              : material.ListView.separated(
                  padding: const material.EdgeInsets.all(16),
                  cacheExtent: 400,
                  itemCount: _documents.length,
                  separatorBuilder: (_, __) => const Gap(8),
                  itemBuilder: (context, i) {
                    final shadcnCs = shadcn.Theme.of(context).colorScheme;
                    return _DocumentCard(
                      document: _documents[i],
                      index: _skip + i,
                      colorScheme: cs,
                      shadcnCs: shadcnCs,
                      onView: () => widget.onDocumentTap?.call(_documents[i]),
                      onDelete: () => _deleteDocument(_documents[i]),
                      onInspectField: (field) =>
                          unawaited(_inspectField(_documents[i], field)),
                    );
                  },
                ),
        ),
        // Pagination bar
        _buildPaginationBar(cs),
      ],
    );
  }

  Widget _buildFilterBar(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    return material.Container(
      padding:
          const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: material.BoxDecoration(
        color: shadcnCs.muted.withValues(alpha: 0.15),
      ),
      child: Row(
        children: [
          material.Icon(material.Icons.filter_list_rounded,
              size: 18, color: shadcnCs.mutedForeground),
          const Gap(10),
          material.Expanded(
            child: TextField(
              controller: _filterController,
              placeholder: const Text(
                r'Filter (JSON / EJSON) e.g. {"_id": {"$oid": "…"}}',
              ),
              onSubmitted: (_) => _applyFilter(),
            ),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: _applyFilter,
            size: ButtonSize.small,
            child: const Text('Apply'),
          ),
          const Gap(4),
          GhostButton(
            onPressed: _clearFilter,
            size: ButtonSize.small,
            child: const Text('Clear'),
          ),
          const Gap(12),
          PrimaryButton(
            onPressed: _addDocument,
            size: ButtonSize.small,
            leading: const material.Icon(material.Icons.add_rounded, size: 16),
            child: const Text('Add Document'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme cs) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.destructive.withValues(alpha: 0.1),
      child: Row(
        children: [
          material.Icon(material.Icons.error_outline_rounded,
              size: 16, color: cs.destructive),
          const Gap(8),
          material.Expanded(
            child: Text(
              _error!,
              style: material.TextStyle(color: cs.destructive, fontSize: 13),
            ),
          ),
          material.InkWell(
            onTap: () => setState(() => _error = null),
            child: material.Icon(material.Icons.close_rounded,
                size: 16, color: cs.destructive),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    final currentPage = (_skip / _limit).floor() + 1;
    final total = _totalCount;
    final shown = _skip + _documents.length;
    final totalPages = total == null ? null : (total / _limit).ceil();
    final from = shown == _skip ? 0 : _skip + 1;
    final to = shown;
    final hasNext = _hasNextPage;

    return material.Container(
      constraints: const material.BoxConstraints(minHeight: 44),
      padding: const material.EdgeInsets.symmetric(horizontal: 16),
      decoration: material.BoxDecoration(
        color: shadcnCs.muted.withValues(alpha: 0.15),
        border: material.Border(
          top: material.BorderSide(
              color: cs.border.withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(total != null
                  ? '$total documents'
                  : '$shown${hasNext ? '+' : ''} documents')
              .muted()
              .small(),
          const Spacer(),
          Text('$from – $to').muted().small(),
          const Gap(16),
          material.InkWell(
            onTap: _skip > 0 ? _goPrevPage : null,
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(
                material.Icons.chevron_left_rounded,
                size: 20,
                color:
                    _skip > 0 ? shadcnCs.foreground : shadcnCs.mutedForeground,
              ),
            ),
          ),
          const Gap(8),
          Text('$currentPage / ${totalPages ?? '?'}').small(),
          const Gap(8),
          material.InkWell(
            onTap: hasNext ? _goNextPage : null,
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 20,
                color: hasNext
                    ? shadcnCs.foreground
                    : shadcnCs.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Document card widget ───────────────────────────────────────────────────

class _DocumentCard extends StatefulWidget {
  const _DocumentCard({
    required this.document,
    required this.index,
    required this.colorScheme,
    required this.shadcnCs,
    required this.onView,
    required this.onDelete,
    required this.onInspectField,
  });

  final Map<String, dynamic> document;
  final int index;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final ValueChanged<String> onInspectField;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _expanded = false;
  late String _keysPreviewText;

  @override
  void initState() {
    super.initState();
    _keysPreviewText = _computeKeysPreview(widget.document);
  }

  @override
  void didUpdateWidget(covariant _DocumentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      _keysPreviewText = _computeKeysPreview(widget.document);
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final scs = widget.shadcnCs;
    final idStr = widget.document['_id']?.toString() ?? '—';

    return material.Container(
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
            color: cs.border.withValues(alpha: 0.3), width: 1),
      ),
      clipBehavior: material.Clip.antiAlias,
      child: material.Material(
        color: cs.card,
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Material(
              color: material.Colors.transparent,
              child: material.InkWell(
                onTap: widget.onView,
                hoverColor: scs.muted.withValues(alpha: 0.15),
                child: material.Padding(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      material.Icon(material.Icons.description_rounded,
                          size: 16, color: scs.mutedForeground),
                      const Gap(8),
                      Text(
                        idStr,
                        style: material.TextStyle(
                            color: cs.primary,
                            fontSize: 13,
                            fontWeight: material.FontWeight.w500),
                      ),
                      const Spacer(),
                      material.InkWell(
                        onTap: _toggleExpanded,
                        borderRadius: material.BorderRadius.circular(4),
                        child: material.Padding(
                          padding: const material.EdgeInsets.all(4),
                          child: material.Icon(
                            _expanded
                                ? material.Icons.expand_less_rounded
                                : material.Icons.expand_more_rounded,
                            size: 18,
                            color: scs.mutedForeground,
                          ),
                        ),
                      ),
                      const Gap(8),
                      _SmallActionButton(
                        icon: material.Icons.edit_rounded,
                        color: context.semanticPalette.action,
                        onTap: widget.onView,
                      ),
                      const Gap(4),
                      _SmallActionButton(
                        icon: material.Icons.delete_rounded,
                        color: context.semanticPalette.destructive,
                        onTap: widget.onDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            material.Padding(
              padding: const material.EdgeInsets.only(
                  left: 16, right: 16, bottom: 10),
              child: _expanded
                  ? MongoFieldList(
                      document: widget.document,
                      colorScheme: cs,
                      shadcnCs: scs,
                      onInspectField: widget.onInspectField,
                    )
                  : Text(
                      _keysPreviewText,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: material.TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: scs.mutedForeground,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _computeKeysPreview(Map<String, dynamic> doc) {
    final keys = doc.keys.where((k) => k != '_id').toList();
    if (keys.isEmpty) return '{ }';
    return keys.join(', ');
  }
}

@material.visibleForTesting
class MongoFieldList extends StatelessWidget {
  const MongoFieldList({
    super.key,
    required this.document,
    required this.colorScheme,
    required this.shadcnCs,
    required this.onInspectField,
  });

  final Map<String, dynamic> document;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final ValueChanged<String> onInspectField;

  Widget _buildFieldRow(String key) {
    final canEdit = key != '_id';
    final display = mongoFieldToDisplay(document[key]);
    final oneLine = display.replaceAll('\n', ' ');
    return material.InkWell(
      onTap: canEdit ? () => onInspectField(key) : null,
      child: material.Padding(
        padding: const material.EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        child: Row(
          children: [
            material.SizedBox(
              width: 120,
              child: Text(
                key,
                overflow: TextOverflow.ellipsis,
                style: material.TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: material.FontWeight.w600,
                  color: colorScheme.foreground,
                ),
              ),
            ),
            const Gap(8),
            material.Expanded(
              child: Text(
                oneLine,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: material.TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: shadcnCs.mutedForeground,
                ),
              ),
            ),
            if (canEdit)
              material.Icon(
                material.Icons.edit_note_rounded,
                size: 16,
                color: shadcnCs.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() => material.Divider(
        height: 1,
        color: colorScheme.border.withValues(alpha: 0.2),
      );

  @override
  Widget build(BuildContext context) {
    final fields = document.keys.toList();
    if (fields.isEmpty) return const material.SizedBox.shrink();

    final decoration = material.BoxDecoration(
      color: colorScheme.muted.withValues(alpha: 0.15),
      borderRadius: material.BorderRadius.circular(6),
      border: material.Border.all(
        color: colorScheme.border.withValues(alpha: 0.3),
      ),
    );

    // For documents with <= 10 fields, render a lightweight Column with zero
    // scroll machinery or shrinkWrap measurement passes.
    if (fields.length <= 10) {
      final children = <Widget>[];
      for (var i = 0; i < fields.length; i++) {
        if (i > 0) children.add(_buildDivider());
        children.add(_buildFieldRow(fields[i]));
      }
      return material.Container(
        decoration: decoration,
        padding: const material.EdgeInsets.symmetric(vertical: 4),
        child: material.Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    // For wide documents (> 10 fields), render a bounded virtualized list
    // without shrinkWrap to avoid layout recalculation spikes on scroll.
    return material.Container(
      constraints: const material.BoxConstraints(maxHeight: 320),
      decoration: decoration,
      child: ListView.separated(
        padding: const material.EdgeInsets.symmetric(vertical: 4),
        itemCount: fields.length,
        separatorBuilder: (_, __) => _buildDivider(),
        itemBuilder: (context, i) => _buildFieldRow(fields[i]),
      ),
    );
  }
}

// ─── Small icon-only action button ──────────────────────────────────────────

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final material.IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return material.IconButton(
      onPressed: onTap,
      icon: material.Icon(icon, size: 15, color: color),
      padding: const material.EdgeInsets.all(5),
      constraints: const material.BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 18,
    );
  }
}
