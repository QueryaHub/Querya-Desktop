import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import 'redis_databases_view.dart';
import 'redis_keys_view.dart';
import 'redis_key_editor.dart';
import 'redis_view.dart';

// ─── Navigation path model ──────────────────────────────────────────────────

class _Crumb {
  const _Crumb(this.label, this.level);
  final String label;
  final _Level level;
}

enum _Level { databases, keys, key }

// ─── Main explorer widget ───────────────────────────────────────────────────

/// Root widget for Redis data browsing.
/// Manages navigation state (breadcrumbs) and the active connection.
class RedisExplorerView extends material.StatefulWidget {
  const RedisExplorerView({super.key, required this.connectionRow});
  final ConnectionRow connectionRow;

  @override
  material.State<RedisExplorerView> createState() => _RedisExplorerViewState();
}

class _RedisExplorerViewState extends material.State<RedisExplorerView> {
  RedisConnection? _connection;
  bool _connecting = true;
  String? _error;

  // View mode
  bool _showStats = false;

  // Navigation state
  int? _selectedDb;
  String? _selectedKey;
  String? _selectedKeyType;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant RedisExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _disconnectCurrent();
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnectCurrent();
    super.dispose();
  }

  void _disconnectCurrent() {
    final conn = _connection;
    _connection = null;
    if (conn != null) {
      conn.disconnect();
    }
  }

  Future<void> _connect() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _error = null;
      _selectedDb = null;
      _selectedKey = null;
      _selectedKeyType = null;
      _showStats = false;
    });
    try {
      final conn =
          RedisService.instance.createConnection(widget.connectionRow);
      await conn.connect();
      if (!mounted) {
        conn.disconnect();
        return;
      }
      setState(() {
        _connection = conn;
        _connecting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connecting = false;
        });
      }
    }
  }

  // ─── Navigation helpers ─────────────────────────────────────────────────

  void _navigateToDb(int db) {
    setState(() {
      _selectedDb = db;
      _selectedKey = null;
      _selectedKeyType = null;
    });
  }

  void _navigateToKey(String key, String type) {
    setState(() {
      _selectedKey = key;
      _selectedKeyType = type;
    });
  }

  void _navigateToDatabases() {
    setState(() {
      _selectedDb = null;
      _selectedKey = null;
      _selectedKeyType = null;
    });
  }

  void _navigateToKeys() {
    setState(() {
      _selectedKey = null;
      _selectedKeyType = null;
    });
  }

  // ─── Breadcrumbs ────────────────────────────────────────────────────────

  List<_Crumb> get _crumbs {
    final list = <_Crumb>[
      _Crumb(widget.connectionRow.name, _Level.databases),
    ];
    if (_selectedDb != null) {
      list.add(_Crumb('db$_selectedDb', _Level.keys));
    }
    if (_selectedKey != null) {
      list.add(_Crumb(_selectedKey!, _Level.key));
    }
    return list;
  }

  void _onCrumbTap(_Crumb crumb) {
    switch (crumb.level) {
      case _Level.databases:
        _navigateToDatabases();
      case _Level.keys:
        _navigateToKeys();
      case _Level.key:
        break;
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Loading state
    if (_connecting) {
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
            const Text('Connecting...').muted().small(),
          ],
        ),
      );
    }

    // Error state
    final err = _error;
    if (err != null) {
      return material.Center(
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(material.Icons.error_outline_rounded,
                  size: 48, color: cs.destructive),
              const Gap(16),
              const Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(err,
                  style: material.TextStyle(
                      color: cs.mutedForeground, fontSize: 13)),
              const Gap(24),
              OutlineButton(
                onPressed: _connect,
                leading: const material.Icon(material.Icons.refresh_rounded,
                    size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final conn = _connection;
    if (conn == null) return const material.SizedBox.shrink();

    // Statistics mode
    if (_showStats) {
      return RedisView(
        key: ValueKey('stats_${widget.connectionRow.id}'),
        connectionRow: widget.connectionRow,
        connection: conn,
        onBack: () => setState(() => _showStats = false),
      );
    }

    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _BreadcrumbBar(
            crumbs: _crumbs,
            onCrumbTap: _onCrumbTap,
            onRefresh: () => setState(() {}),
            onStats: () => setState(() => _showStats = true),
          ),
          const Divider(height: 1),
          material.Expanded(child: _buildContent(conn)),
        ],
      ),
    );
  }

  material.Widget _buildContent(RedisConnection conn) {
    // Key editor
    if (_selectedKey != null && _selectedDb != null) {
      return RedisKeyEditor(
        key: ValueKey('key_${_selectedDb}_$_selectedKey'),
        connection: conn,
        database: _selectedDb!,
        keyName: _selectedKey!,
        keyType: _selectedKeyType ?? 'string',
        onBack: _navigateToKeys,
        onKeyDeleted: _navigateToKeys,
      );
    }

    // Keys list
    if (_selectedDb != null) {
      return RedisKeysView(
        key: ValueKey('keys_$_selectedDb'),
        connection: conn,
        database: _selectedDb!,
        onKeyTap: _navigateToKey,
      );
    }

    // Databases list
    return RedisDatabasesView(
      key: ValueKey(widget.connectionRow.id),
      connection: conn,
      connectionRow: widget.connectionRow,
      onDatabaseTap: _navigateToDb,
    );
  }
}

// ─── Breadcrumb bar ─────────────────────────────────────────────────────────

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.crumbs,
    required this.onCrumbTap,
    required this.onRefresh,
    required this.onStats,
  });

  final List<_Crumb> crumbs;
  final void Function(_Crumb) onCrumbTap;
  final VoidCallback onRefresh;
  final VoidCallback onStats;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.Container(
      height: 44,
      padding: const material.EdgeInsets.symmetric(horizontal: 16),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.3),
      ),
      child: material.Row(
        children: [
          material.Icon(material.Icons.memory_rounded,
              size: 18, color: cs.primary),
          const Gap(10),
          material.Expanded(
            child: material.SingleChildScrollView(
              scrollDirection: material.Axis.horizontal,
              child: material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) ...[
                      material.Padding(
                        padding: const material.EdgeInsets.symmetric(
                            horizontal: 6),
                        child: material.Icon(
                            material.Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.mutedForeground),
                      ),
                    ],
                    _CrumbChip(
                      label: crumbs[i].label,
                      isLast: i == crumbs.length - 1,
                      onTap: i < crumbs.length - 1
                          ? () => onCrumbTap(crumbs[i])
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(8),
          material.Tooltip(
            message: 'Statistics',
            child: material.InkWell(
              onTap: onStats,
              borderRadius: material.BorderRadius.circular(6),
              child: material.Padding(
                padding: const material.EdgeInsets.all(6),
                child: material.Icon(material.Icons.bar_chart_rounded,
                    size: 18, color: cs.mutedForeground),
              ),
            ),
          ),
          const Gap(4),
          material.Tooltip(
            message: 'Refresh',
            child: material.InkWell(
              onTap: onRefresh,
              borderRadius: material.BorderRadius.circular(6),
              child: material.Padding(
                padding: const material.EdgeInsets.all(6),
                child: material.Icon(material.Icons.refresh_rounded,
                    size: 18, color: cs.mutedForeground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrumbChip extends StatefulWidget {
  const _CrumbChip({
    required this.label,
    required this.isLast,
    this.onTap,
  });

  final String label;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  material.State<_CrumbChip> createState() => _CrumbChipState();
}

class _CrumbChipState extends material.State<_CrumbChip> {
  bool _hovered = false;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = shadcn.Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: widget.onTap != null
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.GestureDetector(
        onTap: widget.onTap,
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const material.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: material.BoxDecoration(
            color: _hovered && widget.onTap != null
                ? cs.primary.withValues(alpha: 0.1)
                : material.Colors.transparent,
            borderRadius: material.BorderRadius.circular(4),
          ),
          child: widget.isLast
              ? Text(widget.label).semiBold().small()
              : Text(widget.label,
                      style: material.TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: material.FontWeight.w500))
                  .small(),
        ),
      ),
    );
  }
}
