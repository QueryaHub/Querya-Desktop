import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/postgres_metadata.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

String _formatBytes(int? b) {
  if (b == null) return '—';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Indexes in a schema (pg_indexes-style list).
class PostgresIndexListView extends material.StatefulWidget {
  const PostgresIndexListView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;

  @override
  material.State<PostgresIndexListView> createState() =>
      _PostgresIndexListViewState();
}

class _PostgresIndexListViewState extends material.State<PostgresIndexListView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgIndexRow> _rows = [];
  final _scroll = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lease?.release();
    _lease = null;
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final rows = await lease.connection.listIndexesInSchema(widget.schema);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    if (_loading) {
      return material.Container(
        color: cs.background,
        child: const material.Center(
          child: material.CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.SelectableText(_error!,
              style: material.TextStyle(color: cs.destructive)),
        ),
      );
    }
    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _browserToolbar(
            context,
            title: 'Indexes · ${widget.schema}',
            onRefresh: _load,
          ),
          material.Expanded(
            child: material.Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: material.SingleChildScrollView(
                controller: _scroll,
                padding: const material.EdgeInsets.all(16),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    for (final r in _rows) ...[
                      material.Container(
                        margin: const material.EdgeInsets.only(bottom: 12),
                        padding: const material.EdgeInsets.all(12),
                        decoration: material.BoxDecoration(
                          color: cs.muted.withValues(alpha: 0.12),
                          borderRadius: material.BorderRadius.circular(8),
                          border: material.Border.all(
                              color: cs.border.withValues(alpha: 0.35)),
                        ),
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Text(
                              '${r.tableName} · ${r.indexName}',
                              style: material.TextStyle(
                                fontWeight: material.FontWeight.w600,
                                fontSize: 12,
                                color: cs.foreground,
                              ),
                            ),
                            material.Text(
                              'Size: ${_formatBytes(r.sizeBytes)}',
                              style: material.TextStyle(
                                fontSize: 11,
                                color: cs.mutedForeground,
                              ),
                            ),
                            const Gap(8),
                            material.SelectableText(
                              r.indexDef,
                              style: material.TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.4,
                                color: cs.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_rows.isEmpty)
                      const Text('No indexes in this schema.').muted().small(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Triggers in a schema.
class PostgresTriggerListView extends material.StatefulWidget {
  const PostgresTriggerListView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;

  @override
  material.State<PostgresTriggerListView> createState() =>
      _PostgresTriggerListViewState();
}

class _PostgresTriggerListViewState extends material.State<PostgresTriggerListView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgTriggerRow> _rows = [];
  final _scroll = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lease?.release();
    _lease = null;
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final rows = await lease.connection.listTriggersInSchema(widget.schema);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    if (_loading) {
      return material.Container(
        color: cs.background,
        child: const material.Center(
          child: material.CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return material.Container(
        color: cs.background,
        child: material.Center(
          child: material.SelectableText(_error!,
              style: material.TextStyle(color: cs.destructive)),
        ),
      );
    }
    return material.Container(
      color: cs.background,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          _browserToolbar(
            context,
            title: 'Triggers · ${widget.schema}',
            onRefresh: _load,
          ),
          material.Expanded(
            child: material.Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: material.SingleChildScrollView(
                controller: _scroll,
                padding: const material.EdgeInsets.all(16),
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    for (final r in _rows) ...[
                      material.Container(
                        margin: const material.EdgeInsets.only(bottom: 12),
                        padding: const material.EdgeInsets.all(12),
                        decoration: material.BoxDecoration(
                          color: cs.muted.withValues(alpha: 0.12),
                          borderRadius: material.BorderRadius.circular(8),
                          border: material.Border.all(
                              color: cs.border.withValues(alpha: 0.35)),
                        ),
                        child: material.Column(
                          crossAxisAlignment: material.CrossAxisAlignment.start,
                          children: [
                            material.Text(
                              '${r.tableName} · ${r.triggerName}',
                              style: material.TextStyle(
                                fontWeight: material.FontWeight.w600,
                                fontSize: 12,
                                color: cs.foreground,
                              ),
                            ),
                            const Gap(8),
                            material.SelectableText(
                              r.definition,
                              style: material.TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.4,
                                color: cs.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_rows.isEmpty)
                      const Text('No triggers in this schema.').muted().small(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// User-defined types (enum, domain, composite, …).
class PostgresTypeListView extends material.StatefulWidget {
  const PostgresTypeListView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;

  @override
  material.State<PostgresTypeListView> createState() =>
      _PostgresTypeListViewState();
}

class _PostgresTypeListViewState extends material.State<PostgresTypeListView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgTypeRow> _rows = [];
  final _scroll = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lease?.release();
    _lease = null;
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final rows = await lease.connection.listUserTypesInSchema(widget.schema);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return material.Center(
        child: material.SelectableText(_error!,
            style: material.TextStyle(color: cs.destructive)),
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        _browserToolbar(
          context,
          title: 'Types · ${widget.schema}',
          onRefresh: _load,
        ),
        material.Expanded(
          child: material.Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: material.SingleChildScrollView(
              controller: _scroll,
              padding: const material.EdgeInsets.all(16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  for (final r in _rows)
                    material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 4),
                      child: material.Row(
                        children: [
                          material.Expanded(
                            child: material.Text(
                              r.name,
                              style: material.TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: cs.foreground,
                              ),
                            ),
                          ),
                          material.Container(
                            padding: const material.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: material.BoxDecoration(
                              color: cs.muted.withValues(alpha: 0.35),
                              borderRadius: material.BorderRadius.circular(4),
                            ),
                            child: Text(r.kind).xSmall().muted(),
                          ),
                        ],
                      ),
                    ),
                  if (_rows.isEmpty)
                    const Text('No user types in this schema.').muted().small(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Installed extensions ([pg_extension]).
class PostgresExtensionListView extends material.StatefulWidget {
  const PostgresExtensionListView({
    super.key,
    required this.connectionRow,
    required this.database,
  });

  final ConnectionRow connectionRow;
  final String database;

  @override
  material.State<PostgresExtensionListView> createState() =>
      _PostgresExtensionListViewState();
}

class _PostgresExtensionListViewState
    extends material.State<PostgresExtensionListView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgExtensionRow> _rows = [];
  final _scroll = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lease?.release();
    _lease = null;
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final rows = await lease.connection.listExtensions();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return material.Center(
        child: material.SelectableText(_error!,
            style: material.TextStyle(color: cs.destructive)),
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        _browserToolbar(
          context,
          title: 'Extensions · ${widget.database}',
          onRefresh: _load,
        ),
        material.Expanded(
          child: material.Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: material.SingleChildScrollView(
              controller: _scroll,
              padding: const material.EdgeInsets.all(16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  for (final r in _rows)
                    material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 6),
                      child: material.Row(
                        children: [
                          material.Icon(material.Icons.extension_rounded,
                              size: 16, color: cs.primary),
                          const Gap(8),
                          material.Expanded(
                            child: material.Text(
                              r.name,
                              style: material.TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: material.FontWeight.w600,
                                color: cs.foreground,
                              ),
                            ),
                          ),
                          Text('v${r.version}').muted().xSmall(),
                        ],
                      ),
                    ),
                  if (_rows.isEmpty)
                    const Text('No extensions installed.').muted().small(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Foreign data wrappers and foreign servers.
class PostgresFdwListView extends material.StatefulWidget {
  const PostgresFdwListView({
    super.key,
    required this.connectionRow,
    required this.database,
  });

  final ConnectionRow connectionRow;
  final String database;

  @override
  material.State<PostgresFdwListView> createState() =>
      _PostgresFdwListViewState();
}

class _PostgresFdwListViewState extends material.State<PostgresFdwListView> {
  PgLease? _lease;

  bool _loading = true;
  String? _error;
  List<PgFdwRow> _fdws = [];
  List<PgForeignServerRow> _servers = [];
  final _scroll = material.ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_loading) {
      PostgresService.instance.interrupt(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
    }
    _lease?.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lease?.release();
    _lease = null;
    try {
      final lease = await PostgresService.instance.acquire(
        widget.connectionRow,
        database: widget.database,
        mode: PgSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      final conn = lease.connection;
      final fdws = await conn.listForeignDataWrappers();
      final srv = await conn.listForeignServers();
      if (!mounted) return;
      setState(() {
        _fdws = fdws;
        _servers = srv;
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
    if (_loading) {
      return const material.Center(
        child: material.CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return material.Center(
        child: material.SelectableText(_error!,
            style: material.TextStyle(color: cs.destructive)),
      );
    }
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        _browserToolbar(
          context,
          title: 'Foreign data · ${widget.database}',
          onRefresh: _load,
        ),
        material.Expanded(
          child: material.Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: material.SingleChildScrollView(
              controller: _scroll,
              padding: const material.EdgeInsets.all(16),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Foreign-data wrappers').small().semiBold(),
                  const Gap(8),
                  for (final r in _fdws)
                    material.Padding(
                      padding: const material.EdgeInsets.only(bottom: 8),
                      child: material.Text(
                        '${r.name}${r.handler != null ? ' · ${r.handler}' : ''}',
                        style: material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: cs.foreground,
                        ),
                      ),
                    ),
                  if (_fdws.isEmpty)
                    const Text('No foreign-data wrappers.').muted().xSmall(),
                  const Gap(24),
                  const Text('Foreign servers').small().semiBold(),
                  const Gap(8),
                  for (final r in _servers)
                    material.Padding(
                      padding: const material.EdgeInsets.only(bottom: 8),
                      child: material.Text(
                        '${r.serverName} → ${r.fdwName}',
                        style: material.TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: cs.foreground,
                        ),
                      ),
                    ),
                  if (_servers.isEmpty)
                    const Text('No foreign servers.').muted().xSmall(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

material.Widget _browserToolbar(
  material.BuildContext context, {
  required String title,
  required VoidCallback onRefresh,
}) {
  final cs = Theme.of(context).colorScheme;
  return material.Container(
    padding: const material.EdgeInsets.fromLTRB(16, 10, 16, 10),
    decoration: material.BoxDecoration(
      color: cs.card,
      border: material.Border(
        bottom: material.BorderSide(color: cs.border.withValues(alpha: 0.5)),
      ),
    ),
    child: material.Row(
      children: [
        material.Expanded(
          child: Text(title).semiBold().small(),
        ),
        OutlineButton(
          size: ButtonSize.small,
          onPressed: onRefresh,
          leading: const material.Icon(material.Icons.refresh_rounded, size: 14),
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}
