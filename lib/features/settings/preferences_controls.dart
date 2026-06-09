import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/querya_dropdown.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Helper / hint copy in Preferences — readable on imported themes.
class PreferencesHint extends StatelessWidget {
  const PreferencesHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: cs.popoverForeground.withValues(alpha: 0.72),
      ),
    );
  }
}

/// Preferences dropdown backed by [QueryaDropdown] ([MenuAnchor]).
class PreferencesDropdownMenu<T> extends StatelessWidget {
  const PreferencesDropdownMenu({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.width,
    this.expandToParent = false,
    this.enabled = true,
  });

  final T value;
  final List<material.DropdownMenuEntry<T>> entries;
  final material.ValueChanged<T?> onSelected;

  /// Fixed width for field + menu. Do not pass [double.infinity] — menu glitches.
  final double? width;

  /// Fill [Expanded] parent width without stretching the popup to screen width.
  final bool expandToParent;
  final bool enabled;

  @override
  material.Widget build(material.BuildContext context) {
    final items = [
      for (final entry in entries)
        QueryaDropdownItem<T>(
          value: entry.value,
          label: entry.label,
          enabled: entry.enabled,
        ),
    ];

    return QueryaDropdown<T>(
      value: value,
      items: items,
      enabled: enabled,
      width: width,
      expandToParent: expandToParent,
      onSelected: onSelected,
    );
  }
}
