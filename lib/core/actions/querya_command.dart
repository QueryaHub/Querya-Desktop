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
    this.sourceExtensionId,
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

  /// Package id when this command came from an extension manifest (CP-05).
  final String? sourceExtensionId;

  final void Function(BuildContext context) execute;

  bool enabledIn(BuildContext context) => isEnabled?.call(context) ?? true;

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Lower-cased search text per command, built on first use. An [Expando]
  /// because the class is `const` (no late fields) and commands are immutable.
  static final Expando<String> _haystacks = Expando<String>('QueryaCommand');

  /// [query] trimmed, lower-cased and split on whitespace; empty when the query
  /// is blank. Split once per search, then pass to [matchesParts] for each
  /// command (#1528).
  static List<String> queryParts(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ? const <String>[] : q.split(_whitespace);
  }

  String get _haystack => _haystacks[this] ??= _buildHaystack();

  String _buildHaystack() {
    final tail = id.substring(id.lastIndexOf('.') + 1);
    final buffer = StringBuffer()
      ..write(title.toLowerCase())
      ..write('\n')
      ..write(id.toLowerCase())
      ..write('\n')
      ..write(tail.toLowerCase());
    final category = this.category;
    if (category != null) {
      buffer
        ..write('\n')
        ..write(category.toLowerCase());
    }
    for (final alias in aliases) {
      buffer
        ..write('\n')
        ..write(alias.toLowerCase());
    }
    return buffer.toString();
  }

  /// Case-insensitive match on title, category, aliases, and the last id segment.
  bool matches(String query) => matchesParts(queryParts(query));

  /// Every part of [parts] (from [queryParts]) occurs in the title, id, id
  /// tail, category or an alias. A part has no whitespace, so it can never
  /// match across the `\n` that separates those fields in the haystack.
  bool matchesParts(List<String> parts) {
    if (parts.isEmpty) return true;
    final haystack = _haystack;
    for (final part in parts) {
      if (!haystack.contains(part)) return false;
    }
    return true;
  }
}
