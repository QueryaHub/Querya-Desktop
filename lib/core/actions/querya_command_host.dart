import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';

/// Optional shell hooks for commands that cannot run from [BuildContext] alone.
class QueryaCommandHost extends InheritedWidget {
  const QueryaCommandHost({
    super.key,
    this.onToggleSidebar,
    this.onNewConnection,
    this.onShowQuickSwitcher,
    this.onOpenSchemaObject,
    required super.child,
  });

  final VoidCallback? onToggleSidebar;
  final VoidCallback? onNewConnection;

  /// Opens Quick Switcher; [query] is a prefilled filter (`#users` remainder).
  final void Function(String query)? onShowQuickSwitcher;

  /// Same path as tapping a tree leaf (grid / explorer).
  final void Function(QueryaSchemaObject object)? onOpenSchemaObject;

  static QueryaCommandHost? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<QueryaCommandHost>();
  }

  @override
  bool updateShouldNotify(QueryaCommandHost oldWidget) {
    return onToggleSidebar != oldWidget.onToggleSidebar ||
        onNewConnection != oldWidget.onNewConnection ||
        onShowQuickSwitcher != oldWidget.onShowQuickSwitcher ||
        onOpenSchemaObject != oldWidget.onOpenSchemaObject;
  }
}
