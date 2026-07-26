import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_stagger.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/features/connections/driver_icon.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Task-oriented empty workspace shown before a connection is selected.
class WorkspaceEmptyHero extends StatefulWidget {
  const WorkspaceEmptyHero({
    super.key,
    required this.onNewConnection,
    this.onNewConnectionFromUrl,
    this.onOpenSqlite,
    this.onOpenConnection,
    this.recentConnections,
  });

  final VoidCallback onNewConnection;
  final VoidCallback? onNewConnectionFromUrl;
  final VoidCallback? onOpenSqlite;
  final ValueChanged<ConnectionRow>? onOpenConnection;

  /// When provided (e.g. in tests), skips loading recent connections from storage.
  final List<ConnectionRow>? recentConnections;

  @override
  State<WorkspaceEmptyHero> createState() => _WorkspaceEmptyHeroState();
}

class _WorkspaceEmptyHeroState extends State<WorkspaceEmptyHero> {
  List<ConnectionRow> _recent = const [];
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.recentConnections;
    if (injected != null) {
      _recent = injected;
      _loaded = true;
    } else {
      unawaited(_loadRecent());
    }
  }

  @override
  void didUpdateWidget(covariant WorkspaceEmptyHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final injected = widget.recentConnections;
    if (injected != null) {
      _recent = injected;
      _loaded = true;
    } else if (oldWidget.recentConnections != null) {
      unawaited(_loadRecent());
    }
  }

  Future<void> _loadRecent() async {
    final recentIds = await AppSettings.instance.getRecentConnectionIds();
    final all = await LocalDb.instance.getConnections();
    final byId = <int, ConnectionRow>{
      for (final conn in all)
        if (conn.id != null) conn.id!: conn,
    };

    final ordered = <ConnectionRow>[];
    for (final id in recentIds) {
      final conn = byId.remove(id);
      if (conn != null) ordered.add(conn);
      if (ordered.length >= kMaxRecentConnections) break;
    }

    if (ordered.length < kMaxRecentConnections) {
      final remaining = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final conn in remaining) {
        ordered.add(conn);
        if (ordered.length >= kMaxRecentConnections) break;
      }
    }

    if (!mounted) return;
    setState(() {
      _recent = ordered;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wb = context.workbench;
    final showRecent = _loaded && _recent.isNotEmpty;

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < WindowLayout.compactWindowWidth;
        final horizontal =
            WindowLayout.heroHorizontalPadding(constraints.maxWidth);

        return material.SingleChildScrollView(
          padding: material.EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: compact ? 24 : 48,
          ),
          child: material.Align(
            alignment: material.Alignment.topCenter,
            child: material.ConstrainedBox(
              constraints: const material.BoxConstraints(maxWidth: 720),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Icon(
                    material.Icons.storage_rounded,
                    size: compact ? 38 : 46,
                    color: cs.primary,
                  ),
                  material.SizedBox(height: compact ? 14 : 18),
                  material.Text(
                    'Start working with your data',
                    textAlign: material.TextAlign.center,
                    style: material.TextStyle(
                      color: cs.foreground,
                      fontSize: compact ? 22 : 28,
                      fontWeight: material.FontWeight.w600,
                    ),
                  ),
                  const material.SizedBox(height: 8),
                  material.Text(
                    'Connect to a database or open a local SQLite file.',
                    textAlign: material.TextAlign.center,
                    style: material.TextStyle(
                      color: cs.mutedForeground,
                      fontSize: compact ? 13 : 14,
                    ),
                  ),
                  material.SizedBox(height: compact ? 24 : 32),
                  material.Wrap(
                    alignment: material.WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      PrimaryButton(
                        key: const Key('empty_new_connection'),
                        onPressed: widget.onNewConnection,
                        leading: const material.Icon(
                          material.Icons.add_link_rounded,
                          size: 18,
                        ),
                        child: const Text('New connection'),
                      ),
                      if (widget.onNewConnectionFromUrl != null)
                        OutlineButton(
                          key: const Key('empty_new_from_url'),
                          onPressed: widget.onNewConnectionFromUrl,
                          leading: const material.Icon(
                            material.Icons.link_rounded,
                            size: 18,
                          ),
                          child: const Text('New from URL'),
                        ),
                      if (widget.onOpenSqlite != null)
                        OutlineButton(
                          key: const Key('empty_open_sqlite'),
                          onPressed: widget.onOpenSqlite,
                          leading: const material.Icon(
                            material.Icons.folder_open_rounded,
                            size: 18,
                          ),
                          child: const Text('Open SQLite file'),
                        ),
                    ],
                  ),
                  material.SizedBox(height: compact ? 28 : 40),
                  QueryaFadeSlide(
                    alignment: material.Alignment.topCenter,
                    offset: const material.Offset(0, 0.03),
                    child: showRecent
                        ? _RecentConnectionsSection(
                            key: const material.ValueKey('empty_recent_section'),
                            connections: _recent,
                            onOpenConnection: widget.onOpenConnection,
                            compact: compact,
                          )
                        : _QuickStartSection(
                            key: const material.ValueKey('empty_quick_start'),
                            compact: compact,
                            surface: wb.surface,
                            borderColor:
                                wb.borderSubtle.withValues(alpha: 0.55),
                            foreground: cs.foreground,
                            primary: cs.primary,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickStartSection extends StatelessWidget {
  const _QuickStartSection({
    super.key,
    required this.compact,
    required this.surface,
    required this.borderColor,
    required this.foreground,
    required this.primary,
  });

  final bool compact;
  final material.Color surface;
  final material.Color borderColor;
  final material.Color foreground;
  final material.Color primary;

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: material.EdgeInsets.all(compact ? 16 : 20),
      decoration: material.BoxDecoration(
        color: surface,
        borderRadius: material.BorderRadius.circular(12),
        border: material.Border.all(color: borderColor),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Text(
            'Quick start',
            style: material.TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: material.FontWeight.w600,
            ),
          ),
          const material.SizedBox(height: 12),
          _QuickStartRow(
            icon: material.Icons.dns_rounded,
            title: 'Server databases',
            description:
                'PostgreSQL, MySQL, MongoDB, Redis and extension drivers',
            color: primary,
          ),
          const material.SizedBox(height: 12),
          _QuickStartRow(
            icon: material.Icons.insert_drive_file_rounded,
            title: 'Local database',
            description:
                'Open an existing SQLite file or create a connection',
            color: primary,
          ),
          const material.SizedBox(height: 12),
          _QuickStartRow(
            icon: material.Icons.security_rounded,
            title: 'Credentials stay protected',
            description:
                'Passwords are stored in your operating system secure store',
            color: primary,
          ),
        ],
      ),
    );
  }
}

class _RecentConnectionsSection extends StatelessWidget {
  const _RecentConnectionsSection({
    super.key,
    required this.connections,
    required this.onOpenConnection,
    required this.compact,
  });

  final List<ConnectionRow> connections;
  final ValueChanged<ConnectionRow>? onOpenConnection;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wb = context.workbench;

    return material.Container(
      padding: material.EdgeInsets.all(compact ? 12 : 16),
      decoration: material.BoxDecoration(
        color: wb.surface,
        borderRadius: material.BorderRadius.circular(12),
        border: material.Border.all(
          color: wb.borderSubtle.withValues(alpha: 0.55),
        ),
      ),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Text(
            'Recent connections',
            style: material.TextStyle(
              color: cs.foreground,
              fontSize: 14,
              fontWeight: material.FontWeight.w600,
            ),
          ),
          const material.SizedBox(height: 8),
          QueryaStagger(
            children: [
              for (var i = 0; i < connections.length; i++)
                material.Padding(
                  padding: material.EdgeInsets.only(top: i == 0 ? 0 : 4),
                  child: _RecentConnectionRow(
                    connection: connections[i],
                    onTap: onOpenConnection == null
                        ? null
                        : () => onOpenConnection!(connections[i]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentConnectionRow extends StatelessWidget {
  const _RecentConnectionRow({
    required this.connection,
    required this.onTap,
  });

  final ConnectionRow connection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = _connectionSubtitle(connection);

    return material.Material(
      color: material.Colors.transparent,
      child: material.InkWell(
        key: Key('empty_recent_${connection.id ?? connection.name}'),
        borderRadius: material.BorderRadius.circular(8),
        onTap: onTap,
        child: material.Padding(
          padding: const material.EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          child: material.Row(
            children: [
              DriverIcon(
                size: 20,
                fallbackIcon: _iconForType(connection.type),
                assetPath: _iconAssetForType(connection.type),
              ),
              const material.SizedBox(width: 12),
              material.Expanded(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    material.Text(
                      connection.name.isEmpty
                          ? connection.type
                          : connection.name,
                      maxLines: 1,
                      overflow: material.TextOverflow.ellipsis,
                      style: material.TextStyle(
                        color: cs.foreground,
                        fontSize: 13,
                        fontWeight: material.FontWeight.w500,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const material.SizedBox(height: 2),
                      material.Text(
                        subtitle,
                        maxLines: 1,
                        overflow: material.TextOverflow.ellipsis,
                        style: material.TextStyle(
                          color: cs.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              material.Icon(
                material.Icons.chevron_right_rounded,
                size: 18,
                color: cs.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final material.IconData icon;
  final String title;
  final String description;
  final material.Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return material.Row(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Icon(icon, size: 18, color: color),
        const material.SizedBox(width: 12),
        material.Expanded(
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.start,
            children: [
              material.Text(
                title,
                style: material.TextStyle(
                  color: cs.foreground,
                  fontSize: 13,
                  fontWeight: material.FontWeight.w500,
                ),
              ),
              const material.SizedBox(height: 2),
              material.Text(
                description,
                style: material.TextStyle(
                  color: cs.mutedForeground,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

material.IconData _iconForType(String type) {
  return switch (type) {
    'mongodb' => material.Icons.eco_rounded,
    'postgresql' => material.Icons.storage_rounded,
    'mysql' => material.Icons.table_chart_rounded,
    'redis' => material.Icons.memory_rounded,
    'sqlite' => material.Icons.folder_open_rounded,
    _ => material.Icons.extension_rounded,
  };
}

String? _iconAssetForType(String type) {
  return switch (type) {
    'postgresql' => 'assets/images/postgresql_icon.png',
    'mysql' => 'assets/images/mysql_icon.png',
    'redis' => 'assets/images/redis_icon.png',
    'mongodb' => 'assets/images/mongodb_icon.png',
    _ => null,
  };
}

String _connectionSubtitle(ConnectionRow connection) {
  if (connection.type == 'sqlite') {
    final path = connection.databaseName ?? connection.connectionString;
    return path?.trim().isNotEmpty == true ? path!.trim() : 'SQLite';
  }
  final host = connection.host?.trim();
  if (host == null || host.isEmpty) {
    return connection.type;
  }
  final port = connection.port;
  return port != null ? '$host:$port' : host;
}
