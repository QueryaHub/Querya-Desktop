import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Full-screen JSON editor for a single MongoDB document.
class MongoDocumentEditor extends material.StatefulWidget {
  const MongoDocumentEditor({
    super.key,
    required this.connection,
    required this.database,
    required this.collection,
    required this.document,
    this.refreshToken = 0,
    this.onBack,
    this.onDocumentUpdated,
    this.onDocumentDeleted,
  });

  final MongoConnection connection;
  final String database;
  final String collection;
  final Map<String, dynamic> document;

  /// Incremented by the parent when the user requests a refresh (toolbar).
  final int refreshToken;

  final VoidCallback? onBack;
  final VoidCallback? onDocumentUpdated;
  final VoidCallback? onDocumentDeleted;

  @override
  material.State<MongoDocumentEditor> createState() =>
      _MongoDocumentEditorState();
}

class _MongoDocumentEditorState extends material.State<MongoDocumentEditor> {
  late material.TextEditingController _controller;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  String? _success;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = material.TextEditingController(
      text: _prettyJson(widget.document),
    );
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant MongoDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _reloadFromServer();
    }
  }

  /// Fetches the latest document from the server (toolbar Refresh).
  Future<void> _reloadFromServer() async {
    final id = widget.document['_id'];
    if (id == null) return;
    setState(() {
      _error = null;
      _success = null;
    });
    try {
      final rows = await MongoService.instance.find(
        widget.connection,
        widget.database,
        widget.collection,
        filter: <String, dynamic>{'_id': id},
        limit: 1,
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() => _error = 'Document no longer exists');
        return;
      }
      final doc = rows.first;
      _controller.removeListener(_onTextChanged);
      _controller.text = _prettyJson(doc);
      _controller.addListener(_onTextChanged);
      setState(() {
        _dirty = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to reload: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  void _format() {
    try {
      final parsed = json.decode(_controller.text) as Map<String, dynamic>;
      _controller.text = _prettyJson(parsed);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = 'Invalid JSON: $e');
    }
  }

  Future<void> _save() async {
    final id = widget.document['_id'];
    if (id == null) {
      setState(() => _error = 'Document has no _id field');
      return;
    }

    Map<String, dynamic> parsed;
    try {
      parsed = json.decode(_controller.text) as Map<String, dynamic>;
    } catch (e) {
      setState(() => _error = 'Invalid JSON: $e');
      return;
    }

    // Remove _id from the update payload (can't change _id)
    final updateDoc = Map<String, dynamic>.from(parsed);
    updateDoc.remove('_id');

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    try {
      await MongoService.instance.updateDocument(
        widget.connection,
        widget.database,
        widget.collection,
        {'_id': id},
        {r'$set': updateDoc},
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _success = 'Document saved successfully';
      });
      // Clear success after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _success = null);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save: $e';
        });
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.document['_id'];
    if (id == null) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      await MongoService.instance.deleteDocument(
        widget.connection,
        widget.database,
        widget.collection,
        {'_id': id},
      );
      if (!mounted) return;
      widget.onDocumentDeleted?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = 'Failed to delete: $e';
        });
      }
    }
  }

  String _prettyJson(Map<String, dynamic> doc) {
    try {
      return const JsonEncoder.withIndent('  ').convert(doc);
    } catch (_) {
      return doc.toString();
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    final idStr = widget.document['_id']?.toString() ?? 'New Document';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        material.Container(
          padding:
              const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: material.BoxDecoration(
            color: shadcnCs.muted.withValues(alpha: 0.15),
          ),
          child: Row(
            children: [
              material.InkWell(
                onTap: widget.onBack,
                borderRadius: material.BorderRadius.circular(6),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(4),
                  child: material.Icon(material.Icons.arrow_back_rounded,
                      size: 18, color: shadcnCs.foreground),
                ),
              ),
              const Gap(10),
              material.Icon(material.Icons.description_rounded,
                  size: 16, color: shadcnCs.mutedForeground),
              const Gap(8),
              material.Expanded(
                child: Text(idStr).semiBold().small(),
              ),
              // Format button
              OutlineButton(
                onPressed: _format,
                size: ButtonSize.small,
                leading: const material.Icon(
                    material.Icons.format_align_left_rounded,
                    size: 14),
                child: const Text('Format'),
              ),
              const Gap(8),
              // Save button
              PrimaryButton(
                onPressed: _saving ? null : _save,
                size: ButtonSize.small,
                leading: _saving
                    ? const material.SizedBox(
                        width: 14,
                        height: 14,
                        child: material.CircularProgressIndicator(
                            strokeWidth: 2),
                      )
                    : const material.Icon(material.Icons.save_rounded,
                        size: 14),
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
              const Gap(8),
              // Delete button
              DestructiveButton(
                onPressed: _deleting ? null : _delete,
                size: ButtonSize.small,
                leading: const material.Icon(material.Icons.delete_rounded,
                    size: 14),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
        // Status banners
        if (_error != null)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: cs.destructive.withValues(alpha: 0.1),
            child: Row(
              children: [
                material.Icon(material.Icons.error_outline_rounded,
                    size: 14, color: cs.destructive),
                const Gap(8),
                material.Expanded(
                  child: Text(_error!,
                      style: material.TextStyle(
                          color: cs.destructive, fontSize: 12)),
                ),
                material.InkWell(
                  onTap: () => setState(() => _error = null),
                  child: material.Icon(material.Icons.close_rounded,
                      size: 14, color: cs.destructive),
                ),
              ],
            ),
          ),
        if (_success != null)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            child: Row(
              children: [
                const material.Icon(material.Icons.check_circle_rounded,
                    size: 14, color: Color(0xFF4CAF50)),
                const Gap(8),
                material.Expanded(
                  child: Text(_success!,
                      style: const material.TextStyle(
                          color: Color(0xFF4CAF50), fontSize: 12)),
                ),
              ],
            ),
          ),
        // Editor
        material.Expanded(
          child: material.Container(
            color: cs.card,
            child: material.TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: material.TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: shadcnCs.foreground,
                height: 1.5,
              ),
              decoration: const material.InputDecoration(
                border: material.InputBorder.none,
                contentPadding: material.EdgeInsets.all(16),
              ),
            ),
          ),
        ),
        // Status bar
        material.Container(
          height: 30,
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
              Text('${widget.database} / ${widget.collection}')
                  .muted()
                  .xSmall(),
              const Spacer(),
              if (_dirty)
                Text('Modified',
                        style: material.TextStyle(
                            color: cs.primary, fontSize: 11))
                    .xSmall(),
            ],
          ),
        ),
      ],
    );
  }
}
