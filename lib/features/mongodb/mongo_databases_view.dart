import 'package:flutter/material.dart' as material
    show
        Padding,
        EdgeInsets,
        Container,
        BoxDecoration,
        Border,
        BorderSide,
        BorderRadius,
        Icon,
        IconData,
        Icons,
        Center,
        CrossAxisAlignment,
        MainAxisSize,
        MainAxisAlignment,
        Column,
        SizedBox,
        CircularProgressIndicator,
        Colors,
        FontWeight,
        TextStyle,
        Expanded,
        SingleChildScrollView,
        InkWell,
        MouseRegion,
        SystemMouseCursors,
        AnimatedContainer,
        Curves,
        SelectableText,
        TextEditingController,
        DefaultTextStyle,
        Divider;
import 'package:querya_desktop/core/database/mongodb_connection.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// View that displays MongoDB databases list and server status.
/// Inspired by Mongo Express UI.
class MongoDatabasesView extends StatefulWidget {
  const MongoDatabasesView({
    super.key,
    required this.connectionRow,
  });

  final ConnectionRow connectionRow;

  @override
  State<MongoDatabasesView> createState() => _MongoDatabasesViewState();
}

class _MongoDatabasesViewState extends State<MongoDatabasesView> {
  MongoConnection? _connection;
  List<_DatabaseInfo> _databases = [];
  _ServerStatus? _serverStatus;
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
    if (oldWidget.connectionRow.id != widget.connectionRow.id) {
      _connectAndLoad();
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
      final conn = MongoService.instance.createConnection(widget.connectionRow);
      await conn.connect();
      _connection = conn;
      await _loadDatabases();
      await _loadServerStatus();
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
      for (final name in dbNames) {
        databases.add(_DatabaseInfo(name: name));
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

  Future<void> _loadServerStatus() async {
    if (_connection == null || !_connection!.isConnected) return;

    try {
      final result = await MongoService.instance.executeCommand(
        _connection!,
        'admin',
        {'serverStatus': 1},
      );

      if (mounted) {
        setState(() {
          _serverStatus = _ServerStatus.fromMap(result);
        });
      }
    } catch (_) {
      // Server status is optional — don't fail the whole view
    }
  }

  Future<void> _createDatabase() async {
    final name = _newDbController.text.trim();
    if (name.isEmpty || _connection == null) return;

    try {
      // Creating a collection in a new database effectively creates the database
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            Text('Connecting to ${widget.connectionRow.name}...').muted().small(),
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
              material.Icon(
                material.Icons.error_outline_rounded,
                size: 48,
                color: cs.destructive,
              ),
              const Gap(16),
              Text('Connection Error').large().semiBold(),
              const Gap(8),
              material.SelectableText(
                _error!,
                style: material.TextStyle(
                  color: cs.mutedForeground,
                  fontSize: 13,
                ),
              ),
              const Gap(24),
              OutlineButton(
                onPressed: _connectAndLoad,
                leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return material.Container(
      color: cs.background,
      child: material.SingleChildScrollView(
        padding: const material.EdgeInsets.all(24),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(cs),
            const Gap(24),
            // Databases card
            _buildDatabasesCard(cs),
            const Gap(24),
            // Server status card
            if (_serverStatus != null) _buildServerStatusCard(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Row(
      children: [
        material.Icon(material.Icons.eco_rounded, size: 28, color: cs.primary),
        const Gap(12),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            mainAxisSize: material.MainAxisSize.min,
            children: [
              Text(widget.connectionRow.name).large().semiBold(),
              const Gap(4),
              Text(
                '${widget.connectionRow.host ?? 'localhost'}:${widget.connectionRow.port ?? 27017}',
              ).muted().small(),
            ],
          ),
        ),
        OutlineButton(
          onPressed: _connectAndLoad,
          leading: const material.Icon(material.Icons.refresh_rounded, size: 18),
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildDatabasesCard(ColorScheme cs) {
    return material.Container(
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          // Card header
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.3),
              borderRadius: const material.BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Text('Databases').semiBold(),
                const Spacer(),
                material.SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _newDbController,
                    placeholder: const Text('Database Name'),
                  ),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: _createDatabase,
                  leading: const material.Icon(material.Icons.add_rounded, size: 18),
                  child: const Text('Create Database'),
                ),
              ],
            ),
          ),
          // Database rows
          for (var i = 0; i < _databases.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: cs.border.withValues(alpha: 0.2),
              ),
            _DatabaseRow(
              database: _databases[i],
              colorScheme: cs,
              onView: () {
                // TODO: navigate to collections view
              },
              onDrop: () => _dropDatabase(_databases[i].name),
            ),
          ],
          if (_databases.isEmpty)
            material.Padding(
              padding: const material.EdgeInsets.all(24),
              child: material.Center(
                child: Text('No databases found').muted(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard(ColorScheme cs) {
    final s = _serverStatus!;
    return material.Container(
      decoration: material.BoxDecoration(
        color: cs.card,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          // Card header
          material.Container(
            padding: const material.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: material.BoxDecoration(
              color: cs.muted.withValues(alpha: 0.3),
              borderRadius: const material.BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Text('Server Status').semiBold(),
          ),
          // Status rows
          material.Padding(
            padding: const material.EdgeInsets.all(20),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.stretch,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                // Server info
                _StatusSection(
                  rows: [
                    if (s.host != null) _StatusRow('Hostname', s.host!),
                    if (s.version != null) _StatusRow('MongoDB Version', s.version!),
                    if (s.uptime != null) _StatusRow('Uptime', '${s.uptime} seconds'),
                  ],
                ),
                const Gap(16),
                // Connections
                _StatusSection(
                  rows: [
                    if (s.currentConnections != null)
                      _StatusRow('Current Connections', '${s.currentConnections}'),
                    if (s.availableConnections != null)
                      _StatusRow('Available Connections', '${s.availableConnections}'),
                    if (s.activeClients != null)
                      _StatusRow('Active Clients', '${s.activeClients}'),
                  ],
                ),
                const Gap(16),
                // Operations
                _StatusSection(
                  rows: [
                    if (s.totalInserts != null)
                      _StatusRow('Total Inserts', '${s.totalInserts}'),
                    if (s.totalQueries != null)
                      _StatusRow('Total Queries', '${s.totalQueries}'),
                    if (s.totalUpdates != null)
                      _StatusRow('Total Updates', '${s.totalUpdates}'),
                    if (s.totalDeletes != null)
                      _StatusRow('Total Deletes', '${s.totalDeletes}'),
                  ],
                ),
              ],
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
        color: _hovered ? cs.muted.withValues(alpha: 0.15) : Colors.transparent,
        padding: const material.EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                child: material.DefaultTextStyle(
                  style: material.TextStyle(
                    color: const Color(0xFF42A5F5),
                    fontSize: 15,
                    fontWeight: material.FontWeight.w500,
                  ),
                  child: Text(widget.database.name),
                ),
              ),
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
          padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: material.BoxDecoration(
            color: _hovered
                ? widget.color.withValues(alpha: 0.9)
                : widget.color.withValues(alpha: 0.75),
            borderRadius: material.BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Icon(widget.icon, size: 16, color: material.Colors.white),
              const Gap(6),
              material.DefaultTextStyle(
                style: material.TextStyle(
                  color: material.Colors.white,
                  fontSize: 13,
                  fontWeight: material.FontWeight.w500,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.rows});

  final List<_StatusRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const material.SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return material.Container(
      decoration: material.BoxDecoration(
        border: material.Border.all(
          color: cs.border.withValues(alpha: 0.2),
          width: 1,
        ),
        borderRadius: material.BorderRadius.circular(6),
      ),
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: cs.border.withValues(alpha: 0.15),
              ),
            material.Padding(
              padding: const material.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  material.SizedBox(
                    width: 200,
                    child: Text(rows[i].label).semiBold().small(),
                  ),
                  material.Expanded(
                    child: Text(rows[i].value).muted().small(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow {
  const _StatusRow(this.label, this.value);
  final String label;
  final String value;
}

// ─── Data models ─────────────────────────────────────────────────────────────

class _DatabaseInfo {
  const _DatabaseInfo({required this.name});
  final String name;
}

class _ServerStatus {
  const _ServerStatus({
    this.host,
    this.version,
    this.uptime,
    this.currentConnections,
    this.availableConnections,
    this.activeClients,
    this.totalInserts,
    this.totalQueries,
    this.totalUpdates,
    this.totalDeletes,
  });

  final String? host;
  final String? version;
  final int? uptime;
  final int? currentConnections;
  final int? availableConnections;
  final int? activeClients;
  final int? totalInserts;
  final int? totalQueries;
  final int? totalUpdates;
  final int? totalDeletes;

  factory _ServerStatus.fromMap(Map<String, dynamic> m) {
    final connections = m['connections'] as Map<String, dynamic>?;
    final globalLock = m['globalLock'] as Map<String, dynamic>?;
    final activeClientsMap = globalLock?['activeClients'] as Map<String, dynamic>?;
    final opcounters = m['opcounters'] as Map<String, dynamic>?;

    return _ServerStatus(
      host: m['host'] as String?,
      version: m['version'] as String?,
      uptime: m['uptime'] as int?,
      currentConnections: connections?['current'] as int?,
      availableConnections: connections?['available'] as int?,
      activeClients: activeClientsMap?['total'] as int?,
      totalInserts: opcounters?['insert'] as int?,
      totalQueries: opcounters?['query'] as int?,
      totalUpdates: opcounters?['update'] as int?,
      totalDeletes: opcounters?['delete'] as int?,
    );
  }
}
