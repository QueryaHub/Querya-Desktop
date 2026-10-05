import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/mongodb/mongo_create_index_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongo_index_info.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Interactive view for managing, inspecting, creating, and dropping
/// MongoDB collection indexes with disk size metrics.
class MongoIndexesView extends material.StatefulWidget {
  const MongoIndexesView({
    super.key,
    required this.connection,
    required this.database,
    required this.collection,
    this.onBack,
    this.refreshToken = 0,
    this.initialIndexes,
    this.onFetchIndexes,
    this.onDropIndex,
    this.onCreateIndex,
  });

  final MongoConnection connection;
  final String database;
  final String collection;
  final material.VoidCallback? onBack;
  final int refreshToken;
  final List<MongoIndexInfo>? initialIndexes;
  final Future<List<Map<String, dynamic>>> Function()? onFetchIndexes;
  final Future<void> Function(String name)? onDropIndex;
  final Future<void> Function({
    required Map<String, dynamic> keys,
    String? name,
    bool unique,
    bool sparse,
    int? expireAfterSeconds,
  })? onCreateIndex;

  @override
  material.State<MongoIndexesView> createState() => _MongoIndexesViewState();
}

class _MongoIndexesViewState extends material.State<MongoIndexesView> {
  List<MongoIndexInfo> _indexes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialIndexes != null) {
      _indexes = List.from(widget.initialIndexes!);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant MongoIndexesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.database != widget.database ||
        oldWidget.collection != widget.collection) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rawList = await MongoService.instance.getIndexesWithStats(
        widget.connection,
        widget.database,
        widget.collection,
      );

      if (!mounted) return;
      setState(() {
        _indexes = rawList.map(MongoIndexInfo.fromMap).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  int get _totalSizeBytes {
    int total = 0;
    for (final idx in _indexes) {
      if (idx.sizeBytes != null) {
        total += idx.sizeBytes!;
      }
    }
    return total;
  }

  String get _totalSizeFormatted {
    final bytes = _totalSizeBytes;
    if (bytes == 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openCreateIndexDialog() async {
    final created = await MongoCreateIndexDialog.show(
      context: context,
      connection: widget.connection,
      database: widget.database,
      collection: widget.collection,
      onCreateIndex: widget.onCreateIndex,
    );

    if (created == true) {
      unawaited(_load());
    }
  }

  Future<void> _dropIndex(MongoIndexInfo index) async {
    if (index.isPrimary) {
      showAppToast(
        context: context,
        message: 'Primary index _id_ cannot be dropped',
        variant: AppToastVariant.error,
      );
      return;
    }

    final confirmed = await QueryaConfirmDialog.show(
      context: context,
      title: 'Drop Index',
      message:
          'Are you sure you want to drop index "${index.name}" from collection "${widget.collection}"?',
      confirmLabel: 'Drop Index',
      isDestructive: true,
      icon: material.Icons.delete_forever_rounded,
    );

    if (confirmed != true || !mounted) return;

    try {
      if (widget.onDropIndex != null) {
        await widget.onDropIndex!(index.name);
      } else {
        await MongoService.instance.dropIndex(
          widget.connection,
          widget.database,
          widget.collection,
          index.name,
        );
      }

      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Index "${index.name}" dropped successfully',
        variant: AppToastVariant.success,
      );
      unawaited(_load());
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Failed to drop index: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Header action bar
          _buildHeader(cs),
          const Divider(height: 1),
          // Error banner
          if (_error != null)
            material.Container(
              padding: const material.EdgeInsets.all(12),
              color: cs.destructive.withValues(alpha: 0.1),
              child: material.Row(
                children: [
                  material.Icon(material.Icons.error_outline_rounded,
                      size: 16, color: cs.destructive),
                  const Gap(8),
                  material.Expanded(
                    child: material.SelectableText(
                      _error!,
                      style: material.TextStyle(
                        color: cs.destructive,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  OutlineButton(
                    onPressed: _load,
                    size: ButtonSize.small,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          // Content
          material.Expanded(
            child: _loading
                ? const material.Center(
                    child: QueryaSpinner(
                      size: QueryaSpinnerSize.lg,
                      label: 'Loading collection indexes...',
                    ),
                  )
                : _indexes.isEmpty
                    ? QueryaEmptyState(
                        icon: const material.Icon(
                          material.Icons.layers_clear_rounded,
                          size: 40,
                        ),
                        title: 'No Indexes Found',
                        description:
                            'This collection does not have any index definitions.',
                        actionLabel: 'Create Index',
                        onAction: _openCreateIndexDialog,
                      )
                    : material.ListView.separated(
                        padding: const material.EdgeInsets.all(16),
                        itemCount: _indexes.length,
                        separatorBuilder: (_, __) => const Gap(10),
                        itemBuilder: (context, index) {
                          return _IndexCard(
                            index: _indexes[index],
                            onDrop: () => _dropIndex(_indexes[index]),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  material.Widget _buildHeader(ColorScheme cs) {
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.card,
      child: material.SingleChildScrollView(
        scrollDirection: material.Axis.horizontal,
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            if (widget.onBack != null) ...[
              OutlineButton(
                onPressed: widget.onBack,
                size: ButtonSize.small,
                leading: const material.Icon(material.Icons.arrow_back_rounded,
                    size: 14),
                child: const Text('Back to Documents'),
              ),
              const Gap(12),
            ],
            material.Icon(
              material.Icons.layers_outlined,
              size: 18,
              color: cs.primary,
            ),
            const Gap(8),
            Text('Indexes: ${widget.collection}')
                .semiBold()
                .medium(),
            const Gap(8),
            QueryaBadge.status(
              '${_indexes.length} indexes',
              status: QueryaBadgeStatus.neutral,
            ),
            if (_totalSizeBytes > 0) ...[
              const Gap(8),
              QueryaBadge.status(
                '$_totalSizeFormatted on disk',
                status: QueryaBadgeStatus.info,
              ),
            ],
            const Gap(16),
            QueryaIconButton(
              icon: const material.Icon(material.Icons.refresh_rounded),
              tooltip: 'Refresh Indexes',
              density: QueryaIconButtonDensity.dense,
              onPressed: _load,
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _openCreateIndexDialog,
              size: ButtonSize.small,
              leading:
                  const material.Icon(material.Icons.add_rounded, size: 14),
              child: const Text('Create Index'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Index Card ───────────────────────────────────────────────────────────────

class _IndexCard extends material.StatelessWidget {
  const _IndexCard({
    required this.index,
    required this.onDrop,
  });

  final MongoIndexInfo index;
  final material.VoidCallback onDrop;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: material.Padding(
        padding: const material.EdgeInsets.all(14),
        child: material.Row(
          children: [
            // Leading icon/badge
            material.Container(
              padding: const material.EdgeInsets.all(8),
              decoration: material.BoxDecoration(
                color: index.isPrimary
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.muted.withValues(alpha: 0.15),
                borderRadius: material.BorderRadius.circular(8),
              ),
              child: material.Icon(
                index.isPrimary
                    ? material.Icons.vpn_key_rounded
                    : material.Icons.layers_rounded,
                size: 20,
                color: index.isPrimary ? cs.primary : cs.mutedForeground,
              ),
            ),
            const Gap(14),
            // Info column
            material.Expanded(
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  material.Row(
                    children: [
                      Text(index.name).semiBold(),
                      const Gap(8),
                      if (index.isPrimary)
                        const QueryaBadge.primaryKey(label: 'PRIMARY')
                      else
                        QueryaBadge.status(
                          index.indexType,
                          status: QueryaBadgeStatus.neutral,
                        ),
                      if (index.isUnique && !index.isPrimary) ...[
                        const Gap(6),
                        const QueryaBadge.status(
                          'UNIQUE',
                          status: QueryaBadgeStatus.info,
                        ),
                      ],
                      if (index.isSparse) ...[
                        const Gap(6),
                        const QueryaBadge.status(
                          'SPARSE',
                          status: QueryaBadgeStatus.neutral,
                        ),
                      ],
                      if (index.isTtl) ...[
                        const Gap(6),
                        QueryaBadge.status(
                          'TTL: ${index.expireAfterSeconds}s',
                          status: QueryaBadgeStatus.warning,
                        ),
                      ],
                    ],
                  ),
                  const Gap(4),
                  material.Row(
                    children: [
                      const Text('Keys: ').muted().small(),
                      material.SelectableText(
                        index.keysFormatted,
                        style: const material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: material.FontWeight.w500,
                        ),
                      ),
                      const Gap(16),
                      const Text('Size: ').muted().small(),
                      Text(index.sizeFormatted).small(),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(12),
            // Actions
            if (index.isPrimary)
              const QueryaIconButton(
                icon: material.Icon(material.Icons.lock_outline_rounded),
                tooltip: 'Primary index _id_ cannot be deleted',
                density: QueryaIconButtonDensity.standard,
              )
            else
              QueryaIconButton(
                icon: const material.Icon(material.Icons.delete_outline_rounded),
                tooltip: 'Drop Index',
                density: QueryaIconButtonDensity.standard,
                isDestructive: true,
                onPressed: onDrop,
              ),
          ],
        ),
      ),
    );
  }
}
