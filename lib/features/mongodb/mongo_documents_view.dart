import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
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

class _MongoDocumentsViewState extends material.State<MongoDocumentsView> {
  List<Map<String, dynamic>> _documents = [];
  int _totalCount = 0;
  int _skip = 0;
  final int _limit = _defaultLimit;
  bool _loading = true;
  String? _error;

  final _filterController = material.TextEditingController();
  Map<String, dynamic>? _activeFilter;

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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final count = await MongoService.instance.countDocuments(
        widget.connection,
        widget.database,
        widget.collection,
        filter: _activeFilter,
      );
      final docs = await MongoService.instance.find(
        widget.connection,
        widget.database,
        widget.collection,
        filter: _activeFilter,
        limit: _limit,
        skip: _skip,
      );
      if (!mounted) return;
      setState(() {
        _totalCount = count;
        _documents = docs;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _applyFilter() {
    final text = _filterController.text.trim();
    if (text.isEmpty) {
      _activeFilter = null;
    } else {
      try {
        _activeFilter = json.decode(text) as Map<String, dynamic>;
      } catch (e) {
        setState(() {
          _error = 'Invalid JSON filter: $e';
        });
        return;
      }
    }
    _skip = 0;
    _load();
  }

  void _clearFilter() {
    _filterController.clear();
    _activeFilter = null;
    _skip = 0;
    _load();
  }

  void _goNextPage() {
    if (_skip + _limit < _totalCount) {
      _skip += _limit;
      _load();
    }
  }

  void _goPrevPage() {
    if (_skip > 0) {
      _skip = (_skip - _limit).clamp(0, _totalCount);
      _load();
    }
  }

  Future<void> _addDocument() async {
    try {
      await MongoService.instance.insertDocument(
        widget.connection,
        widget.database,
        widget.collection,
        <String, dynamic>{},
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

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final id = doc['_id'];
    if (id == null) return;
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
        // Document list
        material.Expanded(
          child: material.SingleChildScrollView(
            padding: const material.EdgeInsets.all(16),
            child: _buildDocumentCards(cs),
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
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              placeholder: const Text('Filter (JSON) e.g. {"name": "John"}'),
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
            leading:
                const material.Icon(material.Icons.add_rounded, size: 16),
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

  Widget _buildDocumentCards(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    if (_documents.isEmpty) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(48),
          child: const Text('No documents found').muted(),
        ),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _documents.length; i++) ...[
          if (i > 0) const Gap(8),
          _DocumentCard(
            document: _documents[i],
            index: _skip + i,
            colorScheme: cs,
            shadcnCs: shadcnCs,
            onView: () =>
                widget.onDocumentTap?.call(_documents[i]),
            onDelete: () => _deleteDocument(_documents[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildPaginationBar(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    final currentPage = (_skip / _limit).floor() + 1;
    final totalPages = (_totalCount / _limit).ceil();
    final from = _totalCount == 0 ? 0 : _skip + 1;
    final to = (_skip + _limit).clamp(0, _totalCount);

    return material.Container(
      height: 44,
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
          Text('$_totalCount documents').muted().small(),
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
                color: _skip > 0
                    ? shadcnCs.foreground
                    : shadcnCs.mutedForeground,
              ),
            ),
          ),
          const Gap(8),
          Text('$currentPage / $totalPages').small(),
          const Gap(8),
          material.InkWell(
            onTap: _skip + _limit < _totalCount ? _goNextPage : null,
            child: material.Padding(
              padding: const material.EdgeInsets.all(4),
              child: material.Icon(
                material.Icons.chevron_right_rounded,
                size: 20,
                color: _skip + _limit < _totalCount
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
  });

  final Map<String, dynamic> document;
  final int index;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final VoidCallback onView;
  final VoidCallback onDelete;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _hovered = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final scs = widget.shadcnCs;
    final idStr = widget.document['_id']?.toString() ?? '—';
    final keysPreview = _keysPreview(widget.document);

    return material.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: material.BoxDecoration(
          color: _hovered
              ? scs.muted.withValues(alpha: 0.15)
              : cs.card,
          borderRadius: material.BorderRadius.circular(8),
          border: material.Border.all(
              color: cs.border.withValues(alpha: 0.3), width: 1),
        ),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          mainAxisSize: material.MainAxisSize.min,
          children: [
            // Header row
            material.InkWell(
              onTap: widget.onView,
              borderRadius: material.BorderRadius.circular(8),
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
                    // Expand toggle
                    material.InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
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
                    // View
                    _SmallActionButton(
                      icon: material.Icons.edit_rounded,
                      color: const Color(0xFF42A5F5),
                      onTap: widget.onView,
                    ),
                    const Gap(4),
                    // Delete
                    _SmallActionButton(
                      icon: material.Icons.delete_rounded,
                      color: const Color(0xFFEF5350),
                      onTap: widget.onDelete,
                    ),
                  ],
                ),
              ),
            ),
            // Preview / expanded JSON
            material.Padding(
              padding: const material.EdgeInsets.only(
                  left: 16, right: 16, bottom: 10),
              child: _expanded
                  ? material.SelectableText(
                      _prettyJson(widget.document),
                      style: material.TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: scs.mutedForeground,
                      ),
                    )
                  : Text(
                      keysPreview,
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

  /// Returns a compact list of top-level keys (excluding _id).
  String _keysPreview(Map<String, dynamic> doc) {
    final keys = doc.keys.where((k) => k != '_id').toList();
    if (keys.isEmpty) return '{ }';
    return keys.join(', ');
  }

  String _prettyJson(Map<String, dynamic> doc) {
    try {
      return const JsonEncoder.withIndent('  ').convert(doc);
    } catch (_) {
      return doc.toString();
    }
  }
}

// ─── Small icon-only action button ──────────────────────────────────────────

class _SmallActionButton extends StatefulWidget {
  const _SmallActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final material.IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SmallActionButton> createState() => _SmallActionButtonState();
}

class _SmallActionButtonState extends State<_SmallActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.InkWell(
        onTap: widget.onTap,
        borderRadius: material.BorderRadius.circular(4),
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const material.EdgeInsets.all(5),
          decoration: material.BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: 0.15)
                : material.Colors.transparent,
            borderRadius: material.BorderRadius.circular(4),
          ),
          child: material.Icon(widget.icon, size: 15, color: widget.color),
        ),
      ),
    );
  }
}
