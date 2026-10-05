import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/redis_bulk.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/theme/querya_semantic_palette.dart';
import 'package:querya_desktop/features/workspace/destructive_query_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import 'redis_key_tree_engine.dart';

export 'redis_key_tree_engine.dart' show RedisKeyInfo;

/// View presentation mode for Redis keys: flat list or folder tree.
enum RedisKeyViewMode {
  flat,
  tree,
}

/// Paginated key browser for a Redis database.
class RedisKeysView extends material.StatefulWidget {
  const RedisKeysView({
    super.key,
    required this.connection,
    required this.database,
    this.onKeyTap,
    this.isReadOnly = false,
  });

  final RedisConnection connection;
  final int database;
  final void Function(RedisBulkValue key, String type)? onKeyTap;
  final bool isReadOnly;

  @override
  material.State<RedisKeysView> createState() => _RedisKeysViewState();
}

class _RedisKeysViewState extends material.State<RedisKeysView> {
  List<RedisKeyInfo> _keys = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _cursor = 0;
  bool _hasMore = true;
  int _dbSize = 0;

  RedisKeyViewMode _viewMode = RedisKeyViewMode.flat;
  final _filterController = material.TextEditingController();
  final _delimiterController = material.TextEditingController(text: ':');
  final Set<String> _expandedFolders = <String>{};
  String _matchPattern = '*';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _delimiterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _keys = [];
      _cursor = 0;
      _hasMore = true;
    });
    try {
      await widget.connection.selectDatabase(widget.database);
      _dbSize = await widget.connection.dbSize();
      await _scanBatch();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_viewMode == RedisKeyViewMode.tree && _expandedFolders.isEmpty) {
          final tree = _buildTree();
          _expandedFolders.addAll(tree.rootFolders.map((f) => f.fullPrefix));
        }
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

  Future<void> _scanBatch() async {
    var currentCursor = _cursor;
    final accumulatedKeys = <RedisBulkValue>[];
    const maxIterations = 10;
    var iterations = 0;

    do {
      final (nextCursor, keyNames) = await widget.connection.scan(
        cursor: currentCursor,
        match: _matchPattern.isEmpty ? null : _matchPattern,
        count: 100,
      );
      currentCursor = nextCursor;
      accumulatedKeys.addAll(keyNames);
      iterations++;
    } while (accumulatedKeys.length < 50 &&
        currentCursor != 0 &&
        iterations < maxIterations);

    // One pipelined burst of TYPE+TTL (not N× Future.wait round-trips).
    List<RedisKeyInfo> infos;
    String? typeTtlError;
    if (accumulatedKeys.isNotEmpty) {
      try {
        final metas = await widget.connection.typesAndTtls(accumulatedKeys);
        infos = [
          for (var i = 0; i < accumulatedKeys.length; i++)
            RedisKeyInfo(
              name: accumulatedKeys[i],
              type: metas[i].type,
              ttl: metas[i].ttl,
            ),
        ];
      } catch (e) {
        // Still show keys with unknown type/TTL; surface the failure non-blocking.
        infos = [
          for (final name in accumulatedKeys)
            RedisKeyInfo(name: name, type: 'unknown', ttl: -1),
        ];
        typeTtlError = 'Failed to load key types/TTLs: $e';
      }
    } else {
      infos = [];
    }

    if (!mounted) return;
    setState(() {
      _keys.addAll(infos);
      _cursor = currentCursor;
      _hasMore = currentCursor != 0;
      _error = typeTtlError;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      await _scanBatch();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _applyFilter() {
    final text = _filterController.text.trim();
    _matchPattern = text.isEmpty ? '*' : text;
    _load();
  }

  void _clearFilter() {
    _filterController.clear();
    _matchPattern = '*';
    _load();
  }

  Future<void> _deleteKey(RedisKeyInfo keyInfo) async {
    if (widget.isReadOnly) return;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisDel,
      targetName: '${keyInfo.name.label} (${keyInfo.type})',
      commandPreview: 'DEL ${keyInfo.name.label}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.del(keyInfo.name);
      setState(() {
        _keys.removeWhere((k) => k.name == keyInfo.name);
        _dbSize = (_dbSize - 1).clamp(0, _dbSize);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _deleteFolder(RedisKeyFolderNode folder) async {
    if (widget.isReadOnly) return;
    final keys = folder.allKeys;
    if (keys.isEmpty) return;

    final count = keys.length;
    final confirmed = await confirmDestructiveAction(
      context: context,
      type: DestructiveSqlType.redisDel,
      targetName:
          '${folder.fullPrefix}* ($count ${count == 1 ? 'key' : 'keys'})',
      commandPreview:
          'DEL ${keys.map((k) => k.name.label).take(5).join(' ')}${count > 5 ? ' ... ($count total)' : ''}',
      connectionName: widget.connection.name,
    );
    if (!mounted || !confirmed) return;
    try {
      await widget.connection.selectDatabase(widget.database);
      await widget.connection.delMany(keys.map((k) => k.name));
      setState(() {
        final toRemove = keys.map((k) => k.name).toSet();
        _keys.removeWhere((k) => toRemove.contains(k.name));
        _dbSize = (_dbSize - count).clamp(0, _dbSize);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Delete folder failed: $e');
    }
  }

  RedisKeyTree _buildTree() {
    return RedisKeyTreeEngine.buildTree(
      keys: _keys,
      delimiter: _delimiterController.text,
    );
  }

  Set<String> _collectAllFolderPrefixes(List<RedisKeyFolderNode> folders) {
    final result = <String>{};
    void add(RedisKeyFolderNode f) {
      result.add(f.fullPrefix);
      for (final sub in f.folders) {
        add(sub);
      }
    }

    for (final f in folders) {
      add(f);
    }
    return result;
  }

  List<_TreeItem> _buildVisibleTreeItems(
    RedisKeyTree tree,
    Set<String> expandedFolders,
  ) {
    final items = <_TreeItem>[];

    void addFolder(RedisKeyFolderNode folder, int depth) {
      final isExpanded = expandedFolders.contains(folder.fullPrefix);
      items.add(_FolderTreeItem(
        folder: folder,
        depth: depth,
        isExpanded: isExpanded,
      ));

      if (isExpanded) {
        for (final sub in folder.folders) {
          addFolder(sub, depth + 1);
        }
        for (final leaf in folder.leaves) {
          items.add(_LeafTreeItem(
            leaf: leaf,
            depth: depth + 1,
          ));
        }
      }
    }

    for (final f in tree.rootFolders) {
      addFolder(f, 0);
    }
    for (final l in tree.rootLeaves) {
      items.add(_LeafTreeItem(
        leaf: l,
        depth: 0,
      ));
    }

    return items;
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading && _keys.isEmpty) {
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
            const Text('Scanning keys...').muted().small(),
          ],
        ),
      );
    }

    final material.Widget contentWidget;
    if (_keys.isEmpty) {
      contentWidget = material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(48),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(_hasMore
                      ? 'No keys found in scanned range'
                      : 'No keys found')
                  .muted(),
              if (_hasMore) ...[
                const Gap(16),
                OutlineButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  size: ButtonSize.small,
                  child: _loadingMore
                      ? const Text('Scanning...')
                      : const Text('Continue scanning'),
                ),
              ],
            ],
          ),
        ),
      );
    } else if (_viewMode == RedisKeyViewMode.flat) {
      contentWidget = material.ListView.builder(
        padding: const material.EdgeInsets.all(16),
        cacheExtent: 400,
        itemCount: _keys.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          final shadcnCs = shadcn.Theme.of(context).colorScheme;
          if (i >= _keys.length) {
            return material.Padding(
              padding: const material.EdgeInsets.only(top: 12),
              child: material.Center(
                child: OutlineButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  size: ButtonSize.small,
                  child: _loadingMore
                      ? const Text('Loading...')
                      : Text('Load more (${_keys.length} / $_dbSize)'),
                ),
              ),
            );
          }
          return material.Padding(
            padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
            child: _KeyTile(
              keyInfo: _keys[i],
              colorScheme: cs,
              shadcnCs: shadcnCs,
              palette: context.semanticPalette,
              onTap: () => widget.onKeyTap?.call(_keys[i].name, _keys[i].type),
              onDelete: widget.isReadOnly ? null : () => _deleteKey(_keys[i]),
            ),
          );
        },
      );
    } else {
      final tree = _buildTree();
      final visibleItems = _buildVisibleTreeItems(tree, _expandedFolders);

      contentWidget = material.ListView.builder(
        padding: const material.EdgeInsets.all(16),
        cacheExtent: 400,
        itemCount: visibleItems.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          final shadcnCs = shadcn.Theme.of(context).colorScheme;
          if (i >= visibleItems.length) {
            return material.Padding(
              padding: const material.EdgeInsets.only(top: 12),
              child: material.Center(
                child: OutlineButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  size: ButtonSize.small,
                  child: _loadingMore
                      ? const Text('Loading...')
                      : Text('Load more (${_keys.length} / $_dbSize)'),
                ),
              ),
            );
          }
          final item = visibleItems[i];
          if (item is _FolderTreeItem) {
            return material.Padding(
              padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
              child: _FolderTile(
                folder: item.folder,
                isExpanded: item.isExpanded,
                depth: item.depth,
                colorScheme: cs,
                shadcnCs: shadcnCs,
                palette: context.semanticPalette,
                onToggle: () {
                  setState(() {
                    if (_expandedFolders.contains(item.folder.fullPrefix)) {
                      _expandedFolders.remove(item.folder.fullPrefix);
                    } else {
                      _expandedFolders.add(item.folder.fullPrefix);
                    }
                  });
                },
                onDelete: widget.isReadOnly
                    ? null
                    : () => _deleteFolder(item.folder),
              ),
            );
          } else if (item is _LeafTreeItem) {
            return material.Padding(
              padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
              child: _KeyTile(
                keyInfo: item.leaf.keyInfo,
                displayName: item.leaf.name,
                indent: 16.0 * item.depth,
                colorScheme: cs,
                shadcnCs: shadcnCs,
                palette: context.semanticPalette,
                onTap: () => widget.onKeyTap?.call(
                  item.leaf.keyInfo.name,
                  item.leaf.keyInfo.type,
                ),
                onDelete: widget.isReadOnly
                    ? null
                    : () => _deleteKey(item.leaf.keyInfo),
              ),
            );
          }
          return const material.SizedBox.shrink();
        },
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        _buildFilterBar(cs),
        const Divider(height: 1),
        if (_error != null) _buildErrorBanner(cs),
        material.Expanded(child: contentWidget),
        _buildStatusBar(cs),
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
          material.Icon(material.Icons.search_rounded,
              size: 18, color: shadcnCs.mutedForeground),
          const Gap(10),
          material.Expanded(
            child: TextField(
              controller: _filterController,
              placeholder: const Text('Pattern e.g. user:* or session:*'),
              onSubmitted: (_) => _applyFilter(),
            ),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: _applyFilter,
            size: ButtonSize.small,
            child: const Text('Search'),
          ),
          const Gap(4),
          GhostButton(
            onPressed: _clearFilter,
            size: ButtonSize.small,
            child: const Text('Clear'),
          ),
          material.Container(
            height: 20,
            width: 1,
            margin: const material.EdgeInsets.symmetric(horizontal: 8),
            color: cs.border.withValues(alpha: 0.3),
          ),
          material.SizedBox(
            height: 28,
            child: material.SegmentedButton<RedisKeyViewMode>(
              segments: const [
                material.ButtonSegment(
                  value: RedisKeyViewMode.flat,
                  label: material.Text('Flat'),
                  icon:
                      material.Icon(material.Icons.view_list_rounded, size: 14),
                ),
                material.ButtonSegment(
                  value: RedisKeyViewMode.tree,
                  label: material.Text('Tree'),
                  icon: material.Icon(material.Icons.account_tree_rounded,
                      size: 14),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selected) {
                setState(() {
                  _viewMode = selected.first;
                  if (_viewMode == RedisKeyViewMode.tree &&
                      _expandedFolders.isEmpty) {
                    final tree = _buildTree();
                    _expandedFolders
                        .addAll(tree.rootFolders.map((f) => f.fullPrefix));
                  }
                });
              },
              showSelectedIcon: false,
              style: material.SegmentedButton.styleFrom(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 0),
                visualDensity: material.VisualDensity.compact,
              ),
            ),
          ),
          if (_viewMode == RedisKeyViewMode.tree) ...[
            const Gap(8),
            material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Text(
                  'Sep:',
                  style: material.TextStyle(
                    fontSize: 12,
                    color: shadcnCs.mutedForeground,
                  ),
                ),
                const Gap(4),
                material.SizedBox(
                  width: 36,
                  height: 28,
                  child: material.TextField(
                    controller: _delimiterController,
                    textAlign: material.TextAlign.center,
                    style: const material.TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    decoration: material.InputDecoration(
                      contentPadding: material.EdgeInsets.zero,
                      isDense: true,
                      border: material.OutlineInputBorder(
                        borderRadius: material.BorderRadius.circular(6),
                        borderSide: material.BorderSide(
                          color: cs.border.withValues(alpha: 0.4),
                        ),
                      ),
                      focusedBorder: material.OutlineInputBorder(
                        borderRadius: material.BorderRadius.circular(6),
                        borderSide: material.BorderSide(color: cs.primary),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const Gap(4),
            material.Tooltip(
              message: _expandedFolders.isEmpty
                  ? 'Expand all folders'
                  : 'Collapse all folders',
              child: GhostButton(
                size: ButtonSize.small,
                onPressed: () {
                  setState(() {
                    if (_expandedFolders.isEmpty) {
                      final tree = _buildTree();
                      _expandedFolders.addAll(
                          _collectAllFolderPrefixes(tree.rootFolders));
                    } else {
                      _expandedFolders.clear();
                    }
                  });
                },
                child: material.Icon(
                  _expandedFolders.isEmpty
                      ? material.Icons.unfold_more_rounded
                      : material.Icons.unfold_less_rounded,
                  size: 16,
                ),
              ),
            ),
          ],
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

  Widget _buildStatusBar(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
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
          Text('db${widget.database}').muted().small(),
          const Gap(16),
          Text('$_dbSize total keys').muted().small(),
          if (widget.isReadOnly) ...[
            const Gap(16),
            const Text('Read-only session').muted().small(),
          ],
          const Spacer(),
          if (_viewMode == RedisKeyViewMode.tree) ...[
            Text('Tree (sep: "${_delimiterController.text}")').muted().small(),
            const Gap(16),
          ],
          Text('${_keys.length} loaded').muted().small(),
          if (_hasMore) ...[
            const Gap(8),
            const Text('• more available').muted().xSmall(),
          ],
        ],
      ),
    );
  }
}

// ─── Tree item model ────────────────────────────────────────────────────────

sealed class _TreeItem {
  int get depth;
}

class _FolderTreeItem extends _TreeItem {
  _FolderTreeItem({
    required this.folder,
    required this.depth,
    required this.isExpanded,
  });

  final RedisKeyFolderNode folder;
  @override
  final int depth;
  final bool isExpanded;
}

class _LeafTreeItem extends _TreeItem {
  _LeafTreeItem({
    required this.leaf,
    required this.depth,
  });

  final RedisKeyLeafNode leaf;
  @override
  final int depth;
}

// ─── Folder tile widget ─────────────────────────────────────────────────────

class _FolderTile extends material.StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.isExpanded,
    required this.depth,
    required this.colorScheme,
    required this.shadcnCs,
    required this.palette,
    required this.onToggle,
    this.onDelete,
  });

  final RedisKeyFolderNode folder;
  final bool isExpanded;
  final int depth;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final QueryaSemanticPalette palette;
  final material.VoidCallback onToggle;
  final material.VoidCallback? onDelete;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = colorScheme;
    final indent = 16.0 * depth;

    return material.Material(
      color: cs.card.withValues(alpha: 0.6),
      borderRadius: material.BorderRadius.circular(8),
      clipBehavior: material.Clip.antiAlias,
      child: material.InkWell(
        onTap: onToggle,
        hoverColor: shadcnCs.muted.withValues(alpha: 0.15),
        borderRadius: material.BorderRadius.circular(8),
        child: material.Padding(
          padding: material.EdgeInsets.only(
            left: 12 + indent,
            right: 16,
            top: 8,
            bottom: 8,
          ),
          child: material.Row(
            children: [
              material.AnimatedRotation(
                turns: isExpanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: material.Icon(
                  material.Icons.chevron_right_rounded,
                  size: 18,
                  color: shadcnCs.mutedForeground,
                ),
              ),
              const Gap(6),
              material.Icon(
                isExpanded
                    ? material.Icons.folder_open_rounded
                    : material.Icons.folder_rounded,
                size: 18,
                color: palette.accent,
              ),
              const Gap(8),
              material.Text(
                folder.name,
                style: material.TextStyle(
                  fontSize: 13,
                  fontWeight: material.FontWeight.w600,
                  fontFamily: 'monospace',
                  color: cs.foreground,
                ),
              ),
              const Gap(8),
              material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: material.BoxDecoration(
                  color: shadcnCs.muted.withValues(alpha: 0.3),
                  borderRadius: material.BorderRadius.circular(10),
                ),
                child: material.Text(
                  folder.totalKeyCount == 1
                      ? '1 key'
                      : '${folder.totalKeyCount} keys',
                  style: material.TextStyle(
                    fontSize: 11,
                    color: shadcnCs.mutedForeground,
                    fontWeight: material.FontWeight.w500,
                  ),
                ),
              ),
              const material.Spacer(),
              if (onDelete != null)
                material.IconButton(
                  onPressed: onDelete,
                  icon: material.Icon(
                    material.Icons.delete_outline_rounded,
                    size: 16,
                    color: palette.destructive,
                  ),
                  padding: const material.EdgeInsets.all(4),
                  constraints: const material.BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  splashRadius: 18,
                  tooltip: 'Delete folder (${folder.totalKeyCount} keys)',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Key tile widget ────────────────────────────────────────────────────────

class _KeyTile extends material.StatelessWidget {
  const _KeyTile({
    required this.keyInfo,
    required this.colorScheme,
    required this.shadcnCs,
    required this.palette,
    required this.onTap,
    this.onDelete,
    this.displayName,
    this.indent = 0.0,
  });

  final RedisKeyInfo keyInfo;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final QueryaSemanticPalette palette;
  final material.VoidCallback onTap;
  final material.VoidCallback? onDelete;
  final String? displayName;
  final double indent;

  static Color _typeColor(String type, QueryaSemanticPalette palette) {
    switch (type) {
      case 'string':
        return palette.type1;
      case 'hash':
        return palette.type4;
      case 'list':
        return palette.type2;
      case 'set':
        return palette.type3;
      case 'zset':
        return palette.type5;
      default:
        return palette.muted;
    }
  }

  static material.IconData _typeIcon(String type) {
    switch (type) {
      case 'string':
        return material.Icons.text_fields_rounded;
      case 'hash':
        return material.Icons.tag_rounded;
      case 'list':
        return material.Icons.format_list_numbered_rounded;
      case 'set':
        return material.Icons.scatter_plot_rounded;
      case 'zset':
        return material.Icons.sort_rounded;
      default:
        return material.Icons.help_outline_rounded;
    }
  }

  static String _formatTtl(int ttl) {
    if (ttl == -1) return 'No TTL';
    if (ttl == -2) return 'Missing';
    if (ttl < 60) return '${ttl}s';
    if (ttl < 3600) return '${(ttl / 60).toStringAsFixed(0)}m';
    if (ttl < 86400) return '${(ttl / 3600).toStringAsFixed(1)}h';
    return '${(ttl / 86400).toStringAsFixed(1)}d';
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = colorScheme;
    final ki = keyInfo;
    final typeCol = _typeColor(ki.type, palette);

    return material.Material(
      color: cs.card,
      borderRadius: material.BorderRadius.circular(8),
      clipBehavior: material.Clip.antiAlias,
      child: material.InkWell(
        onTap: onTap,
        hoverColor: shadcnCs.muted.withValues(alpha: 0.15),
        borderRadius: material.BorderRadius.circular(8),
        child: material.Padding(
          padding: material.EdgeInsets.only(
            left: 16 + indent,
            right: 16,
            top: 10,
            bottom: 10,
          ),
          child: material.Row(
            children: [
              material.Icon(_typeIcon(ki.type), size: 16, color: typeCol),
              const Gap(10),
              material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: material.BoxDecoration(
                  color: typeCol.withValues(alpha: 0.12),
                  borderRadius: material.BorderRadius.circular(4),
                ),
                child: material.Text(
                  ki.type.toUpperCase(),
                  style: material.TextStyle(
                    fontSize: 10,
                    fontWeight: material.FontWeight.w600,
                    color: typeCol,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Gap(10),
              material.Expanded(
                child: material.Tooltip(
                  message: ki.name.label,
                  child: material.Text(
                    displayName ?? ki.name.label,
                    overflow: material.TextOverflow.ellipsis,
                    maxLines: 1,
                    style: material.TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: cs.foreground,
                    ),
                  ),
                ),
              ),
              const Gap(8),
              if (ki.ttl >= 0)
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: material.BoxDecoration(
                    color: shadcnCs.muted.withValues(alpha: 0.3),
                    borderRadius: material.BorderRadius.circular(4),
                  ),
                  child: material.Text(
                    'TTL ${_formatTtl(ki.ttl)}',
                    style: material.TextStyle(
                      fontSize: 10,
                      color: shadcnCs.mutedForeground,
                    ),
                  ),
                ),
              const Gap(4),
              if (onDelete != null)
                material.IconButton(
                  onPressed: onDelete,
                  icon: material.Icon(
                    material.Icons.delete_rounded,
                    size: 15,
                    color: palette.destructive,
                  ),
                  padding: const material.EdgeInsets.all(4),
                  constraints: const material.BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  splashRadius: 18,
                  tooltip: 'Delete key',
                ),
              material.Icon(material.Icons.chevron_right_rounded,
                  size: 18, color: shadcnCs.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
