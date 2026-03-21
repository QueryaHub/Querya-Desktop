import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Displays the list of collections in a MongoDB database.
class MongoCollectionsView extends material.StatefulWidget {
  const MongoCollectionsView({
    super.key,
    required this.connection,
    required this.database,
    this.onCollectionTap,
    this.refreshToken = 0,
  });

  final MongoConnection connection;
  final String database;
  final ValueChanged<String>? onCollectionTap;

  /// Incremented by the parent when the user requests a refresh (toolbar).
  final int refreshToken;

  @override
  material.State<MongoCollectionsView> createState() =>
      _MongoCollectionsViewState();
}

class _MongoCollectionsViewState extends material.State<MongoCollectionsView> {
  List<_CollectionInfo> _collections = [];
  bool _loading = true;
  String? _error;

  final _newCollController = material.TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MongoCollectionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _newCollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final names =
          await widget.connection.listCollections(widget.database);
      final collections = <_CollectionInfo>[];
      for (final name in names) {
        int? count;
        int? size;
        try {
          final stats = await MongoService.instance.getCollectionStats(
            widget.connection,
            widget.database,
            name,
          );
          count = _toInt(stats['count']);
          size = _toInt(stats['size']);
        } catch (_) {}
        collections.add(
            _CollectionInfo(name: name, documentCount: count, size: size));
      }
      if (!mounted) return;
      setState(() {
        _collections = collections;
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

  /// Safely converts a BSON/Dart value to [int].
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<void> _createCollection() async {
    final name = _newCollController.text.trim();
    if (name.isEmpty) return;
    try {
      await MongoService.instance.createCollection(
        widget.connection,
        widget.database,
        name,
      );
      _newCollController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to create collection: $e';
        });
      }
    }
  }

  Future<void> _dropCollection(String name) async {
    try {
      await MongoService.instance.dropCollection(
        widget.connection,
        widget.database,
        name,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to drop collection: $e';
        });
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
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
            const Text('Loading collections...').muted().small(),
          ],
        ),
      );
    }

    if (_error != null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(material.Icons.error_outline_rounded,
                  size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(_error!,
                  style: material.TextStyle(
                      color: cs.mutedForeground, fontSize: 13)),
              const Gap(24),
              OutlineButton(
                onPressed: _load,
                leading: const material.Icon(material.Icons.refresh_rounded,
                    size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.all(24),
      child: _buildCard(cs),
    );
  }

  Widget _buildCard(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    return material.Container(
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
            color: cs.border.withValues(alpha: 0.4), width: 1),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          // Card header
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            decoration: material.BoxDecoration(
              color: shadcnCs.muted.withValues(alpha: 0.3),
              borderRadius: const material.BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                material.Icon(material.Icons.folder_rounded,
                    size: 18, color: shadcnCs.primary),
                const Gap(10),
                Text('${widget.database} — Collections (${_collections.length})')
                    .semiBold(),
                const Spacer(),
                material.SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _newCollController,
                    placeholder: const Text('New collection...'),
                  ),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: _createCollection,
                  size: ButtonSize.small,
                  leading: const material.Icon(material.Icons.add_rounded,
                      size: 16),
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
          // Table header
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            decoration: material.BoxDecoration(
              color: shadcnCs.muted.withValues(alpha: 0.15),
            ),
            child: Row(
              children: [
                const material.SizedBox(width: 80),
                material.Expanded(
                    child:
                        const Text('Collection Name').semiBold().xSmall()),
                material.SizedBox(
                    width: 100,
                    child: const Text('Documents').semiBold().xSmall()),
                material.SizedBox(
                    width: 100,
                    child: const Text('Size').semiBold().xSmall()),
                const material.SizedBox(width: 60),
              ],
            ),
          ),
          // Collection rows
          for (var i = 0; i < _collections.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: cs.border.withValues(alpha: 0.15)),
            _CollectionRow(
              collection: _collections[i],
              colorScheme: cs,
              onView: () =>
                  widget.onCollectionTap?.call(_collections[i].name),
              onDrop: () => _dropCollection(_collections[i].name),
            ),
          ],
          if (_collections.isEmpty)
            material.Padding(
              padding: const material.EdgeInsets.all(24),
              child: material.Center(
                child: const Text('No collections found').muted(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Row widget ──────────────────────────────────────────────────────────────

class _CollectionRow extends StatefulWidget {
  const _CollectionRow({
    required this.collection,
    required this.colorScheme,
    required this.onView,
    required this.onDrop,
  });

  final _CollectionInfo collection;
  final ColorScheme colorScheme;
  final VoidCallback onView;
  final VoidCallback onDrop;

  @override
  State<_CollectionRow> createState() => _CollectionRowState();
}

class _CollectionRowState extends State<_CollectionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return material.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: material.Curves.easeOut,
        color: _hovered
            ? cs.muted.withValues(alpha: 0.15)
            : Colors.transparent,
        padding: const material.EdgeInsets.symmetric(
            horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _ActionButton(
              label: 'View',
              icon: material.Icons.visibility_rounded,
              color: const Color(0xFF4CAF50),
              onTap: widget.onView,
            ),
            const Gap(16),
            material.Expanded(
              child: material.InkWell(
                onTap: widget.onView,
                child: Text(
                  widget.collection.name,
                  style: material.TextStyle(
                    color: cs.primary,
                    fontSize: 14,
                    fontWeight: material.FontWeight.w500,
                  ),
                ),
              ),
            ),
            material.SizedBox(
              width: 100,
              child: Text(widget.collection.documentCount?.toString() ?? '—')
                  .muted()
                  .small(),
            ),
            material.SizedBox(
              width: 100,
              child: Text(_formatSize(widget.collection.size))
                  .muted()
                  .small(),
            ),
            _ActionButton(
              label: 'Del',
              icon: material.Icons.delete_rounded,
              color: const Color(0xFFEF5350),
              onTap: widget.onDrop,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final material.IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.InkWell(
        onTap: widget.onTap,
        borderRadius: material.BorderRadius.circular(6),
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: material.Curves.easeOut,
          padding: const material.EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: material.BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: 0.9)
                : widget.color.withValues(alpha: 0.75),
            borderRadius: material.BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(widget.icon,
                  size: 14, color: material.Colors.white),
              const Gap(5),
              Text(
                widget.label,
                style: const material.TextStyle(
                  color: material.Colors.white,
                  fontSize: 12,
                  fontWeight: material.FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data model ──────────────────────────────────────────────────────────────

class _CollectionInfo {
  const _CollectionInfo({
    required this.name,
    this.documentCount,
    this.size,
  });

  final String name;
  final int? documentCount;
  final int? size;
}
