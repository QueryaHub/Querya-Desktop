import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Paginated key browser for a Redis database.
class RedisKeysView extends material.StatefulWidget {
  const RedisKeysView({
    super.key,
    required this.connection,
    required this.database,
    this.onKeyTap,
  });

  final RedisConnection connection;
  final int database;
  final void Function(String key, String type)? onKeyTap;

  @override
  material.State<RedisKeysView> createState() => _RedisKeysViewState();
}

class _RedisKeysViewState extends material.State<RedisKeysView> {
  List<_KeyInfo> _keys = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _cursor = 0;
  bool _hasMore = true;
  int _dbSize = 0;

  final _filterController = material.TextEditingController();
  String _matchPattern = '*';

  @override
  void initState() {
    super.initState();
    _load();
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
      _keys = [];
      _cursor = 0;
      _hasMore = true;
    });
    try {
      await widget.connection.selectDatabase(widget.database);
      _dbSize = await widget.connection.dbSize();
      await _scanBatch();
      if (!mounted) return;
      setState(() => _loading = false);
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
    final (nextCursor, keyNames) = await widget.connection.scan(
      cursor: _cursor,
      match: _matchPattern.isEmpty ? null : _matchPattern,
      count: 100,
    );

    // Fetch type and TTL for each key
    final infos = <_KeyInfo>[];
    for (final name in keyNames) {
      try {
        final type = await widget.connection.keyType(name);
        final ttl = await widget.connection.ttl(name);
        infos.add(_KeyInfo(name: name, type: type, ttl: ttl));
      } catch (_) {
        infos.add(_KeyInfo(name: name, type: 'unknown', ttl: -1));
      }
    }

    if (!mounted) return;
    setState(() {
      _keys.addAll(infos);
      _cursor = nextCursor;
      _hasMore = nextCursor != 0;
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

  Future<void> _deleteKey(_KeyInfo keyInfo) async {
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

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        _buildFilterBar(cs),
        const Divider(height: 1),
        if (_error != null) _buildErrorBanner(cs),
        material.Expanded(
          child: material.SingleChildScrollView(
            padding: const material.EdgeInsets.all(16),
            child: _buildKeysList(cs),
          ),
        ),
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
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme cs) {
    return material.Container(
      padding:
          const material.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.destructive.withValues(alpha: 0.1),
      child: Row(
        children: [
          material.Icon(material.Icons.error_outline_rounded,
              size: 16, color: cs.destructive),
          const Gap(8),
          material.Expanded(
            child: Text(
              _error!,
              style:
                  material.TextStyle(color: cs.destructive, fontSize: 13),
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

  Widget _buildKeysList(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
    if (_keys.isEmpty) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(48),
          child: const Text('No keys found').muted(),
        ),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _keys.length; i++) ...[
          if (i > 0) const Gap(4),
          _KeyTile(
            keyInfo: _keys[i],
            colorScheme: cs,
            shadcnCs: shadcnCs,
            onTap: () =>
                widget.onKeyTap?.call(_keys[i].name, _keys[i].type),
            onDelete: () => _deleteKey(_keys[i]),
          ),
        ],
        if (_hasMore) ...[
          const Gap(12),
          material.Center(
            child: OutlineButton(
              onPressed: _loadingMore ? null : _loadMore,
              size: ButtonSize.small,
              child: _loadingMore
                  ? const Text('Loading...')
                  : Text('Load more (${_keys.length} / $_dbSize)'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusBar(ColorScheme cs) {
    final shadcnCs = shadcn.Theme.of(context).colorScheme;
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
          Text('db${widget.database}').muted().small(),
          const Gap(16),
          Text('$_dbSize total keys').muted().small(),
          const Spacer(),
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

// ─── Key info model ─────────────────────────────────────────────────────────

class _KeyInfo {
  const _KeyInfo({
    required this.name,
    required this.type,
    required this.ttl,
  });
  final String name;
  final String type;
  final int ttl; // -1 = no expiry, -2 = key doesn't exist
}

// ─── Key tile widget ────────────────────────────────────────────────────────

class _KeyTile extends StatefulWidget {
  const _KeyTile({
    required this.keyInfo,
    required this.colorScheme,
    required this.shadcnCs,
    required this.onTap,
    required this.onDelete,
  });

  final _KeyInfo keyInfo;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  material.State<_KeyTile> createState() => _KeyTileState();
}

class _KeyTileState extends material.State<_KeyTile> {
  bool _hovered = false;

  Color _typeColor(String type) {
    switch (type) {
      case 'string':
        return const Color(0xFF42A5F5);
      case 'hash':
        return const Color(0xFFAB47BC);
      case 'list':
        return const Color(0xFF66BB6A);
      case 'set':
        return const Color(0xFFFFA726);
      case 'zset':
        return const Color(0xFFEF5350);
      default:
        return widget.shadcnCs.mutedForeground;
    }
  }

  material.IconData _typeIcon(String type) {
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

  String _formatTtl(int ttl) {
    if (ttl == -1) return 'No TTL';
    if (ttl == -2) return 'Missing';
    if (ttl < 60) return '${ttl}s';
    if (ttl < 3600) return '${(ttl / 60).toStringAsFixed(0)}m';
    if (ttl < 86400) return '${(ttl / 3600).toStringAsFixed(1)}h';
    return '${(ttl / 86400).toStringAsFixed(1)}d';
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = widget.colorScheme;
    final scs = widget.shadcnCs;
    final ki = widget.keyInfo;
    final typeCol = _typeColor(ki.type);

    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.InkWell(
        onTap: widget.onTap,
        borderRadius: material.BorderRadius.circular(8),
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const material.EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          decoration: material.BoxDecoration(
            color: _hovered
                ? scs.muted.withValues(alpha: 0.15)
                : cs.card,
            borderRadius: material.BorderRadius.circular(8),
            border: material.Border.all(
                color: cs.border.withValues(alpha: 0.3), width: 1),
          ),
          child: material.Row(
            children: [
              material.Icon(_typeIcon(ki.type), size: 16, color: typeCol),
              const Gap(10),
              // Type badge
              material.Container(
                padding: const material.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: material.BoxDecoration(
                  color: typeCol.withValues(alpha: 0.12),
                  borderRadius: material.BorderRadius.circular(4),
                ),
                child: Text(
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
              // Key name
              material.Expanded(
                child: material.Text(
                  ki.name,
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 1,
                  style: material.TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: cs.foreground,
                  ),
                ),
              ),
              const Gap(8),
              // TTL
              if (ki.ttl >= 0)
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: material.BoxDecoration(
                    color: scs.muted.withValues(alpha: 0.3),
                    borderRadius: material.BorderRadius.circular(4),
                  ),
                  child: Text(
                    'TTL ${_formatTtl(ki.ttl)}',
                    style: material.TextStyle(
                      fontSize: 10,
                      color: scs.mutedForeground,
                    ),
                  ),
                ),
              const Gap(8),
              // Delete button (only on hover)
              material.AnimatedOpacity(
                opacity: _hovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: material.InkWell(
                  onTap: widget.onDelete,
                  borderRadius: material.BorderRadius.circular(4),
                  child: const material.Padding(
                    padding: material.EdgeInsets.all(4),
                    child: material.Icon(material.Icons.delete_rounded,
                        size: 15, color: Color(0xFFEF5350)),
                  ),
                ),
              ),
              material.Icon(material.Icons.chevron_right_rounded,
                  size: 18, color: scs.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
