import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// View that displays MongoDB databases list and server status.
class MongoDatabasesView extends StatefulWidget {
  const MongoDatabasesView({
    super.key,
    required this.connectionRow,
    this.connection,
    this.onDatabaseTap,
    this.refreshToken = 0,
  });

  final ConnectionRow connectionRow;

  /// An already-open [MongoConnection]. When provided the view re-uses it
  /// instead of creating (and potentially killing) a new one.
  final MongoConnection? connection;

  /// Called when the user taps a database row to browse it.
  final ValueChanged<String>? onDatabaseTap;

  /// Incremented by the parent when the user requests a refresh (toolbar).
  final int refreshToken;

  @override
  State<MongoDatabasesView> createState() => _MongoDatabasesViewState();
}

class _MongoDatabasesViewState extends State<MongoDatabasesView> {
  MongoConnection? _connection;
  List<_DatabaseInfo> _databases = [];
  bool _isLoading = true;
  String? _error;

  final _newDbController = material.TextEditingController();

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant MongoDatabasesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.connection != widget.connection) {
      _connectAndLoad();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadDatabases();
    }
  }

  @override
  void dispose() {
    _newDbController.dispose();
    super.dispose();
  }

  Future<void> _connectAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Re-use the connection supplied by the parent (MongoExplorerView) when
      // available so we don't create a second connection that replaces the
      // shared one in MongoService.
      final MongoConnection conn;
      if (widget.connection != null) {
        conn = widget.connection!;
        if (!conn.isConnected) {
          await conn.connect();
        }
      } else {
        conn = await MongoService.instance.ensureConnected(widget.connectionRow);
      }
      if (!mounted) return;
      _connection = conn;
      await _loadDatabases();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDatabases() async {
    if (_connection == null || !_connection!.isConnected) return;

    try {
      final dbNames = await _connection!.listDatabases();
      final databases = <_DatabaseInfo>[];

      // Try to fetch sizes via listDatabases command
      Map<String, dynamic>? dbListResult;
      try {
        dbListResult = await MongoService.instance.executeCommand(
          _connection!,
          'admin',
          {'listDatabases': 1},
        );
      } catch (_) {}

      final dbList =
          dbListResult?['databases'] as List<dynamic>? ?? <dynamic>[];

      for (final name in dbNames) {
        int? sizeOnDisk;
        for (final entry in dbList) {
          if (entry is Map && entry['name'] == name) {
            sizeOnDisk = _toInt(entry['sizeOnDisk']);
            break;
          }
        }
        databases.add(_DatabaseInfo(name: name, sizeOnDisk: sizeOnDisk));
      }

      if (mounted) {
        setState(() {
          _databases = databases;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to list databases: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Safely converts a BSON/Dart value to [int].
  /// Handles [int], [num], and bson `Int64` (which is not a [num]).
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    // bson Int64 has a toInt() method but is not a Dart num.
    return int.tryParse(v.toString());
  }

  Future<void> _createDatabase() async {
    final name = _newDbController.text.trim();
    if (name.isEmpty || _connection == null) return;

    try {
      await MongoService.instance.executeCommand(
        _connection!,
        name,
        {'create': 'init'},
      );
      _newDbController.clear();
      await _loadDatabases();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to create database: $e';
        });
      }
    }
  }

  Future<void> _dropDatabase(String name) async {
    if (_connection == null) return;

    try {
      await MongoService.instance.executeCommand(
        _connection!,
        name,
        {'dropDatabase': 1},
      );
      await _loadDatabases();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to drop database: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
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
              const Text('Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(
                _error!,
                style: material.TextStyle(
                    color: cs.mutedForeground, fontSize: 13),
              ),
              const Gap(24),
              OutlineButton(
                onPressed: _connectAndLoad,
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
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _buildDatabasesCard(cs),
        ],
      ),
    );
  }

  Widget _buildDatabasesCard(ColorScheme cs) {
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
                material.Icon(material.Icons.storage_rounded,
                    size: 18, color: shadcnCs.primary),
                const Gap(10),
                Text('Databases (${_databases.length})').semiBold(),
                const Spacer(),
                material.SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _newDbController,
                    placeholder: const Text('New database...'),
                  ),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: _createDatabase,
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
                    child: const Text('Database Name').semiBold().xSmall()),
                material.SizedBox(
                    width: 120,
                    child: const Text('Size').semiBold().xSmall()),
                const material.SizedBox(width: 60),
              ],
            ),
          ),
          // Database rows
          for (var i = 0; i < _databases.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: cs.border.withValues(alpha: 0.15)),
            _DatabaseRow(
              database: _databases[i],
              colorScheme: cs,
              onView: () => widget.onDatabaseTap?.call(_databases[i].name),
              onDrop: () => _dropDatabase(_databases[i].name),
            ),
          ],
          if (_databases.isEmpty)
            material.Padding(
              padding: const material.EdgeInsets.all(24),
              child: material.Center(
                child: const Text('No databases found').muted(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Helper widgets ──────────────────────────────────────────────────────────

class _DatabaseRow extends StatefulWidget {
  const _DatabaseRow({
    required this.database,
    required this.colorScheme,
    required this.onView,
    required this.onDrop,
  });

  final _DatabaseInfo database;
  final ColorScheme colorScheme;
  final VoidCallback onView;
  final VoidCallback onDrop;

  @override
  State<_DatabaseRow> createState() => _DatabaseRowState();
}

class _DatabaseRowState extends State<_DatabaseRow> {
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
            // View button
            _ActionButton(
              label: 'View',
              icon: material.Icons.visibility_rounded,
              color: const Color(0xFF4CAF50),
              onTap: widget.onView,
            ),
            const Gap(16),
            // Database name
            material.Expanded(
              child: material.InkWell(
                onTap: widget.onView,
                child: Text(
                  widget.database.name,
                  style: material.TextStyle(
                    color: cs.primary,
                    fontSize: 14,
                    fontWeight: material.FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Size
            material.SizedBox(
              width: 120,
              child: Text(_formatSize(widget.database.sizeOnDisk))
                  .muted()
                  .small(),
            ),
            // Delete button
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

// ─── Data models ─────────────────────────────────────────────────────────────

class _DatabaseInfo {
  const _DatabaseInfo({required this.name, this.sizeOnDisk});
  final String name;
  final int? sizeOnDisk;
}
