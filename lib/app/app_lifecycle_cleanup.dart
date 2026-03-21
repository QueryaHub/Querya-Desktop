import 'dart:async';

import 'package:flutter/widgets.dart';

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
    unawaited(disconnectAllExternalServices());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(disconnectAllExternalServices());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
