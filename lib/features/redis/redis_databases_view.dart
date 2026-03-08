import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/redis_info.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Shows all Redis databases (db0–dbN) with key counts.
class RedisDatabasesView extends material.StatefulWidget {
  const RedisDatabasesView({
    super.key,
    required this.connection,
    required this.connectionRow,
    this.onDatabaseTap,
  });

  final RedisConnection connection;
  final ConnectionRow connectionRow;
  final ValueChanged<int>? onDatabaseTap;

  @override
  material.State<RedisDatabasesView> createState() =>
      _RedisDatabasesViewState();
}

class _RedisDatabasesViewState extends material.State<RedisDatabasesView> {
  List<_DbInfo> _databases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conn = widget.connection;

      // Get max databases
      final maxDbs = await conn.getMaxDatabases();

      // Get keyspace info from INFO command
      final raw = await conn.info();
      final info = parseRedisInfo(raw);
      final keyspace = info['Keyspace'] ?? {};

      // Build database list
      final dbs = <_DbInfo>[];
      for (var i = 0; i < maxDbs; i++) {
        final dbKey = 'db$i';
        final data = keyspace[dbKey];
        int keys = 0;
        int expires = 0;
        if (data != null) {
          // Parse "keys=X,expires=Y,avg_ttl=Z"
          for (final part in data.split(',')) {
            final kv = part.split('=');
            if (kv.length == 2) {
              if (kv[0].trim() == 'keys') {
                keys = int.tryParse(kv[1].trim()) ?? 0;
              }
              if (kv[0].trim() == 'expires') {
                expires = int.tryParse(kv[1].trim()) ?? 0;
              }
            }
          }
        }
        dbs.add(_DbInfo(index: i, keys: keys, expires: expires, hasData: data != null));
      }

      if (!mounted) return;
      setState(() {
        _databases = dbs;
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

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shadcnCs = shadcn.Theme.of(context).colorScheme;

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
            const Text('Loading databases...').muted().small(),
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
              Text(_error!,
                  style: material.TextStyle(
                      color: cs.destructive, fontSize: 13)),
              const Gap(16),
              OutlineButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final dbsWithData = _databases.where((d) => d.hasData).toList();
    final dbsEmpty = _databases.where((d) => !d.hasData).toList();
    final totalKeys =
        _databases.fold<int>(0, (sum, d) => sum + d.keys);

    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.all(16),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          // Header
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
                material.Icon(material.Icons.storage_rounded,
                    size: 18, color: shadcnCs.primary),
                const Gap(10),
                Text('Databases (${_databases.length})').semiBold(),
                const Spacer(),
                Text('Total keys: $totalKeys').muted().small(),
              ],
            ),
          ),

          // Databases with data
          material.Container(
            decoration: material.BoxDecoration(
              border: material.Border.all(
                  color: cs.border.withValues(alpha: 0.3)),
              borderRadius: const material.BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              children: [
                if (dbsWithData.isNotEmpty) ...[
                  material.Padding(
                    padding: const material.EdgeInsets.only(
                        left: 20, top: 12, bottom: 4),
                    child: const Text('Active databases').muted().xSmall(),
                  ),
                  for (final db in dbsWithData)
                    _DatabaseTile(
                      db: db,
                      colorScheme: cs,
                      shadcnCs: shadcnCs,
                      onTap: () => widget.onDatabaseTap?.call(db.index),
                    ),
                ],
                if (dbsEmpty.isNotEmpty) ...[
                  material.Padding(
                    padding: const material.EdgeInsets.only(
                        left: 20, top: 12, bottom: 4),
                    child: const Text('Empty databases').muted().xSmall(),
                  ),
                  for (final db in dbsEmpty)
                    _DatabaseTile(
                      db: db,
                      colorScheme: cs,
                      shadcnCs: shadcnCs,
                      onTap: () => widget.onDatabaseTap?.call(db.index),
                    ),
                ],
                const Gap(8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Model ──────────────────────────────────────────────────────────────────

class _DbInfo {
  const _DbInfo({
    required this.index,
    required this.keys,
    required this.expires,
    required this.hasData,
  });
  final int index;
  final int keys;
  final int expires;
  final bool hasData;
}

// ─── Tile widget ────────────────────────────────────────────────────────────

class _DatabaseTile extends StatefulWidget {
  const _DatabaseTile({
    required this.db,
    required this.colorScheme,
    required this.shadcnCs,
    required this.onTap,
  });

  final _DbInfo db;
  final ColorScheme colorScheme;
  final shadcn.ColorScheme shadcnCs;
  final VoidCallback onTap;

  @override
  material.State<_DatabaseTile> createState() => _DatabaseTileState();
}

class _DatabaseTileState extends material.State<_DatabaseTile> {
  bool _hovered = false;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = widget.colorScheme;
    final scs = widget.shadcnCs;
    final db = widget.db;

    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: material.InkWell(
        onTap: widget.onTap,
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const material.EdgeInsets.symmetric(
              horizontal: 20, vertical: 10),
          color: _hovered
              ? scs.primary.withValues(alpha: 0.06)
              : material.Colors.transparent,
          child: material.Row(
            children: [
              material.Icon(
                db.hasData
                    ? material.Icons.dns_rounded
                    : material.Icons.dns_outlined,
                size: 18,
                color: db.hasData ? scs.primary : scs.mutedForeground,
              ),
              const Gap(12),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    Text('db${db.index}',
                        style: material.TextStyle(
                          fontSize: 14,
                          fontWeight: material.FontWeight.w500,
                          color: cs.foreground,
                        )),
                    if (db.hasData)
                      Text(
                        '${db.keys} keys • ${db.expires} with TTL',
                        style: material.TextStyle(
                          fontSize: 12,
                          color: scs.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (db.hasData)
                material.Container(
                  padding: const material.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: material.BoxDecoration(
                    color: scs.primary.withValues(alpha: 0.12),
                    borderRadius: material.BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${db.keys}',
                    style: material.TextStyle(
                      fontSize: 11,
                      fontWeight: material.FontWeight.w600,
                      color: scs.primary,
                    ),
                  ),
                ),
              const Gap(8),
              material.Icon(material.Icons.chevron_right_rounded,
                  size: 18, color: scs.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
