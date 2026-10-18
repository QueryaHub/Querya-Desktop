import 'dart:math' show min;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_ui_colors.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_cache.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Displays the list of collections in a MongoDB database.
class MongoCollectionsView extends material.StatefulWidget {
  const MongoCollectionsView({
    super.key,
    required this.connection,
    required this.database,
    this.onCollectionTap,
    this.onOpenQueryConsole,
    this.refreshToken = 0,
  });

  final MongoConnection connection;
  final String database;
  final ValueChanged<String>? onCollectionTap;
  final material.VoidCallback? onOpenQueryConsole;

  /// Incremented by the parent when the user requests a refresh (toolbar).
  final int refreshToken;

  @override
  material.State<MongoCollectionsView> createState() =>
      _MongoCollectionsViewState();
}

/// Parallel [collStats] calls per batch (limits load on large clusters).
const _statsConcurrency = 6;

class _MongoCollectionsViewState extends material.State<MongoCollectionsView> {
  List<_CollectionInfo> _collections = [];
  bool _loading = true;
  String? _error;

  /// Incremented on each full reload so in-flight stats work is ignored after dispose / new load.
  int _loadGeneration = 0;
  bool _loadingStats = false;
  int _statsProgress = 0;
  int _statsTotal = 0;

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
    _loadGeneration++;
    _newCollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadingStats = false;
      _statsProgress = 0;
      _statsTotal = 0;
    });
    try {
      final names = await widget.connection.listCollections(widget.database);
      if (!mounted || gen != _loadGeneration) return;

      setState(() {
        _collections = [
          for (final n in names)
            _CollectionInfo(name: n, documentCount: null, size: null),
        ];
        _loading = false;
        _loadingStats = names.isNotEmpty;
        _statsTotal = names.length;
        _statsProgress = 0;
      });
      QueryaSchemaObjectCache.instance.merge(
        widget.connection.id,
        QueryaSchemaObjectCache.scopeMongo(widget.database),
        [
          for (final name in names)
            QueryaSchemaObject.mongo(
              database: widget.database,
              name: name,
            ),
        ],
      );

      if (names.isEmpty) return;

      for (var i = 0; i < names.length; i += _statsConcurrency) {
        if (!mounted || gen != _loadGeneration) return;
        final end = min(i + _statsConcurrency, names.length);
        final chunk = names.sublist(i, end);

        final chunkInfos = await Future.wait(
          chunk.map((name) async {
            try {
              final stats = await MongoService.instance.getCollectionStats(
                widget.connection,
                widget.database,
                name,
              );
              return _CollectionInfo(
                name: name,
                documentCount: _toInt(stats['count']),
                size: _toInt(stats['size']),
              );
            } catch (_) {
              return _CollectionInfo(
                  name: name, documentCount: null, size: null);
            }
          }),
        );

        if (!mounted || gen != _loadGeneration) return;
        setState(() {
          for (var k = 0; k < chunk.length; k++) {
            _collections[i + k] = chunkInfos[k];
          }
          _statsProgress = end;
          if (end >= names.length) {
            _loadingStats = false;
          }
        });
      }
    } catch (e) {
      if (mounted && gen == _loadGeneration) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadingStats = false;
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
    final confirmed = await confirmDestructiveMongoAction(
      context: context,
      type: DestructiveSqlType.dropCollection,
      targetName: name,
      commandPreview: 'db.$name.drop()',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;

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
    final cs = context.colors;

    if (_loading) {
      return const material.Center(
        child: QueryaSpinner(
          size: QueryaSpinnerSize.lg,
          label: 'Loading collections...',
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
              QueryaButton.secondary(
                label: 'Retry',
                icon: material.Icons.refresh_rounded,
                onPressed: _load,
                size: QueryaControlSize.md,
              ),
            ],
          ),
        ),
      );
    }

    return material.Padding(
      padding: const material.EdgeInsets.all(24),
      child: _buildCard(cs),
    );
  }

  Widget _buildCard(QueryaUiColors cs) {
    final shadcnCs = context.colors;
    return material.Container(
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
            color: cs.border.withValues(alpha: 0.4), width: 1),
      ),
      clipBehavior: material.Clip.antiAlias,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
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
                material.Expanded(
                  child: material.Column(
                    crossAxisAlignment: material.CrossAxisAlignment.start,
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.database} — Collections (${_collections.length})',
                      ).semiBold(),
                      if (_loadingStats && _statsTotal > 0)
                        material.Padding(
                          padding: const material.EdgeInsets.only(top: 4),
                          child: Text(
                            'Loading stats $_statsProgress / $_statsTotal…',
                          ).muted().xSmall(),
                        ),
                    ],
                  ),
                ),
                if (widget.onOpenQueryConsole != null) ...[
                  QueryaButton.secondary(
                    label: 'MQL Console',
                    icon: material.Icons.terminal_rounded,
                    onPressed: widget.onOpenQueryConsole,
                    size: QueryaControlSize.sm,
                  ),
                  const Gap(8),
                ],
                material.SizedBox(
                  width: 180,
                  child: QueryaTextField(
                    controller: _newCollController,
                    placeholder: 'New collection...',
                  ),
                ),
                const Gap(8),
                QueryaButton.primary(
                  label: 'Create',
                  icon: material.Icons.add_rounded,
                  onPressed: _createCollection,
                  size: QueryaControlSize.sm,
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
                    child: const Text('Collection Name').semiBold().xSmall()),
                material.SizedBox(
                    width: 100,
                    child: const Text('Documents').semiBold().xSmall()),
                material.SizedBox(
                    width: 100, child: const Text('Size').semiBold().xSmall()),
                const material.SizedBox(width: 60),
              ],
            ),
          ),
          // Collection rows (virtualized)
          material.Expanded(
            child: _collections.isEmpty
                ? material.Center(
                    child: const Text('No collections found').muted(),
                  )
                : material.ListView.separated(
                    cacheExtent: 400,
                    itemCount: _collections.length,
                    separatorBuilder: (_, __) => QueryaDivider(
                      height: 1,
                      color: cs.border.withValues(alpha: 0.15),
                    ),
                    itemBuilder: (context, i) {
                      return _CollectionRow(
                        collection: _collections[i],
                        colors: cs,
                        onView: () =>
                            widget.onCollectionTap?.call(_collections[i].name),
                        onDrop: () => _dropCollection(_collections[i].name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Row widget ──────────────────────────────────────────────────────────────

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.collection,
    required this.colors,
    required this.onView,
    required this.onDrop,
  });

  final _CollectionInfo collection;
  final QueryaUiColors colors;
  final VoidCallback onView;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final cs = colors;
    return material.Material(
      color: Colors.transparent,
      child: material.InkWell(
        onTap: onView,
        hoverColor: cs.muted.withValues(alpha: 0.15),
        child: material.Padding(
          padding:
              const material.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              QueryaButton.secondary(
                label: 'View',
                icon: material.Icons.visibility_rounded,
                size: QueryaControlSize.sm,
                onPressed: onView,
              ),
              const Gap(16),
              Expanded(
                child: Text(
                  collection.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: material.TextStyle(
                    color: cs.primary,
                    fontSize: 14,
                    fontWeight: material.FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(collection.documentCount?.toString() ?? '—')
                    .muted()
                    .small(),
              ),
              SizedBox(
                width: 100,
                child: Text(_formatSize(collection.size)).muted().small(),
              ),
              QueryaButton.secondary(
                label: 'Del',
                icon: material.Icons.delete_rounded,
                size: QueryaControlSize.sm,
                tone: QueryaButtonTone.destructive,
                onPressed: onDrop,
              ),
            ],
          ),
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
