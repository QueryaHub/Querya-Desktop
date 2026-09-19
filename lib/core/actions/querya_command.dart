import 'package:flutter/widgets.dart';

/// A palette / menubar action with optional enablement and search aliases.
@immutable
class QueryaCommand {
  const QueryaCommand({
    required this.id,
    required this.title,
    required this.execute,
    this.category,
    this.icon,
    this.shortcutLabel,
    this.aliases = const [],
    this.isEnabled,
  });

  /// Stable id (`querya.sql.execute`, `ext.clickhouse.cluster_status`).
  final String id;

  final String title;
  final String? category;
  final IconData? icon;

  /// Display-only accelerator (`Ctrl+Enter`).
  final String? shortcutLabel;

  /// Extra search terms (`dark` → toggle theme).
  final List<String> aliases;

  /// When null, the command is always available.
  final bool Function(BuildContext context)? isEnabled;

  final void Function(BuildContext context) execute;

  bool enabledIn(BuildContext context) => isEnabled?.call(context) ?? true;

  /// Case-insensitive match on title, category, aliases, and the last id segment.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final idTail = id.split('.').last.toLowerCase();
    final fields = <String>[
      title.toLowerCase(),
      id.toLowerCase(),
      idTail,
      if (category != null) category!.toLowerCase(),
      ...aliases.map((a) => a.toLowerCase()),
    ];
    return q.split(RegExp(r'\s+')).every(
          (part) => fields.any((field) => field.contains(part)),
        );
  }
}
