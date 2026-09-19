import 'package:flutter/widgets.dart';

/// Optional shell hooks for commands that cannot run from [BuildContext] alone.
class QueryaCommandHost extends InheritedWidget {
  const QueryaCommandHost({
    super.key,
    this.onToggleSidebar,
    this.onNewConnection,
    required super.child,
  });

  final VoidCallback? onToggleSidebar;
  final VoidCallback? onNewConnection;

  static QueryaCommandHost? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<QueryaCommandHost>();
  }

  @override
  bool updateShouldNotify(QueryaCommandHost oldWidget) {
    return onToggleSidebar != oldWidget.onToggleSidebar ||
        onNewConnection != oldWidget.onNewConnection;
  }
}
