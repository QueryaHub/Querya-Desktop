import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/mcp/mcp_access_store.dart';
import 'package:querya_desktop/core/mcp/mcp_client_config.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/mcp/mcp_server_controller.dart';
import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Preferences → MCP Server (#1136): enable the in-app MCP server, choose the
/// connections AI clients may read, copy client configs, see recent calls.
class PreferencesMcpSection extends material.StatefulWidget {
  const PreferencesMcpSection({
    super.key,
    this.controller,
    this.access,
    this.loadConnections,
    this.loadActivity,
    this.clearActivity,
    this.shimPath,
  });

  final McpServerController? controller;
  final McpAccessSettings? access;
  final Future<List<ConnectionRow>> Function()? loadConnections;
  final Future<List<McpActivityEntry>> Function()? loadActivity;
  final Future<void> Function()? clearActivity;

  /// Overrides the bundled `querya-mcp` lookup (tests).
  final String? shimPath;

  @override
  material.State<PreferencesMcpSection> createState() =>
      PreferencesMcpSectionState();
}

class PreferencesMcpSectionState extends material.State<PreferencesMcpSection> {
  McpServerController get _controller =>
      widget.controller ?? McpServerController.instance;
  McpAccessSettings get _access => widget.access ?? McpAccessStore.instance;

  bool _enabled = false;
  bool _busy = false;

  /// False until the first load ends: nothing that depends on the stored state
  /// (the switch, the connection list, the log) is drawn before that, so the
  /// pane never shows "off" / "no connections" and then jumps to the truth.
  bool _loaded = false;
  List<ConnectionRow> _connections = const [];
  Set<int> _shared = {};
  List<McpActivityEntry> _activity = const [];
  StreamSubscription<Object?>? _callsSub;
  late final String? _shimPath =
      widget.shimPath ?? McpClientConfig.bundledShimPath();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Reload the log after each call (the controller persists it first).
    _callsSub = _controller.calls.listen((_) {
      unawaited(Future<void>.delayed(
          const Duration(milliseconds: 200), _loadActivity));
    });
  }

  @override
  void dispose() {
    unawaited(_callsSub?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await _controller.isEnabled();
    final all = await (widget.loadConnections ??
        () => LocalDb.instance.getConnections())();
    final shared = await _access.readableIds();
    if (!mounted) return;
    List<McpActivityEntry> activity = const [];
    try {
      activity = await (widget.loadActivity ??
          () => LocalDb.instance.listMcpActivity(limit: 50))();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _connections = [
        for (final c in all)
          if (c.id != null && _mcpReadable(c.type)) c,
      ];
      _shared = shared;
      _activity = activity;
      _loaded = true;
    });
  }

  /// The connection types an MCP client can read: the SQL tools and MongoDB.
  static bool _mcpReadable(String type) =>
      McpQueryService.dialectOf(type) != null || type == 'mongodb';

  Future<void> _loadActivity() async {
    try {
      final list = await (widget.loadActivity ??
          () => LocalDb.instance.listMcpActivity(limit: 50))();
      if (mounted) setState(() => _activity = list);
    } catch (_) {}
  }

  Future<void> _setEnabled(bool v) async {
    setState(() {
      _busy = true;
      _enabled = v;
    });
    try {
      await _controller.setEnabled(v);
    } catch (e) {
      if (mounted) {
        setState(() => _enabled = false);
        showAppToast(
          context: context,
          message: 'MCP server did not start: $e',
          variant: AppToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setShared(int id, bool v) async {
    setState(() => v ? _shared.add(id) : _shared.remove(id));
    await _access.setReadable(id, v);
  }

  Future<void> _copy(McpClientKind kind) async {
    final path = _shimPath ?? '/path/to/${McpClientConfig.executableName}';
    await Clipboard.setData(
        ClipboardData(text: McpClientConfig.snippet(kind, path)));
    if (!mounted) return;
    showAppToast(
      context: context,
      message:
          '${kind.label} config copied. Paste it into ${kind.configLocation}.',
      variant: AppToastVariant.success,
    );
  }

  Future<void> _regenerate() async {
    setState(() => _busy = true);
    try {
      await _controller.regenerateToken();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLog() async {
    await (widget.clearActivity ?? LocalDb.instance.clearMcpActivity)();
    await _loadActivity();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('MCP Server').semiBold().small().foreground(),
        const material.SizedBox(height: 6),
        const PreferencesHint(
          'Lets AI clients (Claude Desktop, Cursor, VS Code, Gemini CLI, ...) '
          'read the connections you share below. Read-only: writes are '
          'refused, and no host, user or password is ever sent to the model.',
        ),
        const material.SizedBox(height: 14),
        if (!_loaded)
          const material.Padding(
            padding: material.EdgeInsets.symmetric(vertical: 24),
            child: material.Center(
              child: QueryaSpinner(size: QueryaSpinnerSize.md),
            ),
          )
        else ...[
          PreferencesSwitchRow(
            key: const material.ValueKey('mcp_enabled'),
            value: _enabled,
            enabled: !_busy,
            title: const Text('Enable MCP server').small(),
            subtitle: material.ValueListenableBuilder<McpServerStatus>(
              valueListenable: _controller.status,
              builder: (context, s, _) => Text(_statusText(s)).muted().xSmall(),
            ),
            onChanged: (v) => unawaited(_setEnabled(v)),
          ),
          const material.SizedBox(height: 18),
          _connectionsBlock(),
          const material.SizedBox(height: 18),
          _clientsBlock(),
          const material.SizedBox(height: 18),
          _activityBlock(),
        ],
      ],
    );
  }

  static String _typeLabel(String type) => switch (type) {
        'postgresql' => 'PostgreSQL',
        'mysql' => 'MySQL',
        'sqlite' => 'SQLite',
        'mongodb' => 'MongoDB',
        _ => type,
      };

  String _statusText(McpServerStatus s) {
    if (s.error != null) return 'Not running: ${s.error}';
    if (!s.running) return 'Stopped. AI clients cannot connect.';
    final clients = s.clients == 1 ? '1 client' : '${s.clients} clients';
    return 'Running on 127.0.0.1:${s.port} · $clients connected';
  }

  material.Widget _connectionsBlock() {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('Shared connections').semiBold().small().foreground(),
        const material.SizedBox(height: 4),
        const PreferencesHint(
          'Only switched-on connections are visible to MCP clients. '
          'PostgreSQL, MySQL, SQLite and MongoDB.',
        ),
        const material.SizedBox(height: 8),
        if (_connections.isEmpty)
          const QueryaEmptyState(
            compact: true,
            title: 'No connections to share',
            description:
                'Add a PostgreSQL, MySQL, SQLite or MongoDB connection first.',
          )
        else
          for (final c in _connections)
            PreferencesSwitchRow(
              key: material.ValueKey('mcp_share_${c.id}'),
              value: _shared.contains(c.id),
              title: material.Row(
                children: [
                  material.Flexible(child: Text(c.name).small()),
                  const material.SizedBox(width: 8),
                  QueryaBadge(label: _typeLabel(c.type)),
                  if (c.environment == ConnectionEnvironment.production) ...[
                    const material.SizedBox(width: 6),
                    const QueryaBadge.status('PROD',
                        status: QueryaBadgeStatus.warning),
                  ],
                ],
              ),
              subtitle: c.environment == ConnectionEnvironment.production
                  ? const Text(
                      'Production: the model can read all data this user can.',
                    ).muted().xSmall()
                  : null,
              onChanged: (v) => unawaited(_setShared(c.id!, v)),
            ),
      ],
    );
  }

  material.Widget _clientsBlock() {
    final wb = context.workbench;
    final shim = _shimPath;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('Connect a client').semiBold().small().foreground(),
        const material.SizedBox(height: 4),
        PreferencesHint(shim != null
            ? 'Copy the config for your client and paste it where it keeps MCP '
                'servers. The client starts querya-mcp, which talks to this '
                'running app:'
            : 'querya-mcp is not bundled with this build. Download it from the '
                'GitHub release, then replace this path in the copied config:'),
        const material.SizedBox(height: 6),
        // The path on its own line, unbroken, so it can be read whole.
        material.Container(
          key: const material.ValueKey('mcp_shim_path'),
          width: double.infinity,
          padding:
              const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: material.BoxDecoration(
            color: wb.mutedForeground.withValues(alpha: 0.08),
            borderRadius: material.BorderRadius.circular(6),
          ),
          child: material.Text(
            shim ?? '/path/to/${McpClientConfig.executableName}',
            maxLines: 1,
            overflow: material.TextOverflow.ellipsis,
            style: material.TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: wb.mutedForeground,
            ),
          ),
        ),
        const material.SizedBox(height: 10),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in McpClientKind.values)
              QueryaButton.secondary(
                key: material.ValueKey('mcp_copy_${kind.name}'),
                label: kind == McpClientKind.generic
                    ? 'Copy stdio config'
                    : 'Copy ${kind.label} config',
                tooltip: kind == McpClientKind.generic
                    ? 'For any other client that starts MCP servers over stdio'
                    : null,
                icon: material.Icons.copy_rounded,
                size: QueryaControlSize.md,
                onPressed: () => unawaited(_copy(kind)),
              ),
          ],
        ),
        const material.SizedBox(height: 18),
        // A different kind of action from copying: it cuts connected clients
        // off, so it gets its own row with the consequence spelled out.
        material.Row(
          children: [
            material.Expanded(
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.start,
                children: [
                  const Text('Access token').small(),
                  const material.SizedBox(height: 2),
                  const PreferencesHint(
                    'Regenerating disconnects the connected clients; they '
                    'reconnect on their next start.',
                  ),
                ],
              ),
            ),
            const material.SizedBox(width: 16),
            QueryaButton.secondary(
              key: const material.ValueKey('mcp_regenerate'),
              label: 'Regenerate',
              icon: material.Icons.key_rounded,
              size: QueryaControlSize.md,
              tooltip:
                  _enabled ? null : 'Turn the MCP server on to regenerate.',
              onPressed:
                  _enabled && !_busy ? () => unawaited(_regenerate()) : null,
            ),
          ],
        ),
      ],
    );
  }

  material.Widget _activityBlock() {
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        material.Row(
          children: [
            const Text('Recent calls').semiBold().small().foreground(),
            const material.Spacer(),
            QueryaButton.ghost(
              key: const material.ValueKey('mcp_clear_log'),
              label: 'Clear',
              size: QueryaControlSize.sm,
              onPressed:
                  _activity.isEmpty ? null : () => unawaited(_clearLog()),
            ),
          ],
        ),
        const material.SizedBox(height: 6),
        if (_activity.isEmpty)
          const QueryaEmptyState(
            compact: true,
            title: 'No calls yet',
            description: 'Tool calls from MCP clients appear here.',
          )
        else
          for (var i = 0; i < _activity.length; i++)
            _ActivityRow(entry: _activity[i], first: i == 0),
      ],
    );
  }
}

class _ActivityRow extends material.StatelessWidget {
  const _ActivityRow({required this.entry, this.first = false});

  final McpActivityEntry entry;

  /// The first row has no divider above it.
  final bool first;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final at = DateTime.tryParse(entry.recordedAt)?.toLocal();
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}:'
            '${at.second.toString().padLeft(2, '0')}';
    final refused = entry.refusalRule != null;
    final failed = entry.error != null;
    final (icon, iconColor) = refused
        ? (material.Icons.block_rounded, wb.warning)
        : failed
            ? (material.Icons.error_outline_rounded, wb.destructive)
            : (material.Icons.check_circle_outline_rounded, wb.success);
    final result = failed
        ? entry.error!
        : '${entry.rowCount != null ? '${entry.rowCount} row(s) · ' : ''}'
            '${entry.durationMs} ms';

    return material.Container(
      padding: const material.EdgeInsets.symmetric(vertical: 8),
      decoration: first
          ? null
          : material.BoxDecoration(
              border: material.Border(
                top: material.BorderSide(color: wb.borderSubtle),
              ),
            ),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.only(top: 1),
            child: material.Icon(icon, size: 15, color: iconColor),
          ),
          const material.SizedBox(width: 10),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Row(
                  children: [
                    Text(entry.tool).small().semiBold(),
                    // Takes the free space, so the name is cut only when the
                    // row really is too narrow, and pushes the time right.
                    material.Expanded(
                      child: Text(
                        entry.connectionName == null
                            ? ''
                            : '  ·  ${entry.connectionName}',
                        maxLines: 1,
                        overflow: material.TextOverflow.ellipsis,
                      ).small().muted(),
                    ),
                    const material.SizedBox(width: 8),
                    Text('${entry.client}  $time').xSmall().muted(),
                  ],
                ),
                if (entry.sqlText != null) ...[
                  const material.SizedBox(height: 3),
                  Text(
                    entry.sqlText!,
                    maxLines: 2,
                    overflow: material.TextOverflow.ellipsis,
                    style: material.TextStyle(
                      fontFamily: 'monospace',
                      color: wb.mutedForeground,
                    ),
                  ).xSmall(),
                ],
                const material.SizedBox(height: 3),
                material.Row(
                  children: [
                    material.Flexible(
                      child: Text(
                        result,
                        maxLines: 2,
                        overflow: material.TextOverflow.ellipsis,
                        style: material.TextStyle(
                          color: failed ? wb.destructive : wb.mutedForeground,
                        ),
                      ).xSmall(),
                    ),
                    // The guard rule that refused the call.
                    if (refused) ...[
                      const material.SizedBox(width: 8),
                      QueryaBadge.status(
                        'refused: ${entry.refusalRule}',
                        status: QueryaBadgeStatus.warning,
                      ),
                    ],
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
