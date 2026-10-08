import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:querya_desktop/core/mcp/mcp_server_controller.dart';

import 'app_shutdown.dart';

/// Closes pooled TCP connections when the app is shutting down.
///
/// Uses [AppLifecycleState.detached] and [dispose] so desktop window close is
/// covered as reliably as the platform allows.
class AppLifecycleCleanup extends StatefulWidget {
  const AppLifecycleCleanup({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleCleanup> createState() => _AppLifecycleCleanupState();
}

class _AppLifecycleCleanupState extends State<AppLifecycleCleanup>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_shutdown());
    }
  }

  /// Stops the MCP server first, so no client starts a query on a pool that
  /// is being closed, and removes its endpoint file.
  Future<void> _shutdown() async {
    await McpServerController.instance.stop();
    await disconnectAllExternalServices();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
