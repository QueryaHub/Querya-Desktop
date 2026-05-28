import 'package:flutter/material.dart' as material;
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

/// Material 3 dropdown anchored to the field (stable inside scroll views).
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
  final ValueChanged<T?> onSelected;

  /// Fixed width for field + menu. Do not pass [double.infinity] — menu glitches.
  final double? width;

  /// Fill [Expanded] parent width without stretching the popup to screen width.
  final bool expandToParent;
  final bool enabled;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mTheme = material.Theme.of(context);
    final textStyle = material.TextStyle(
      color: cs.popoverForeground,
      fontSize: 14,
    );

    return material.Theme(
      data: mTheme.copyWith(
        canvasColor: cs.popover,
        colorScheme: mTheme.colorScheme.copyWith(
          surface: cs.popover,
          onSurface: cs.popoverForeground,
        ),
      ),
      child: material.DropdownMenu<T>(
        enabled: enabled,
        width: width,
        expandedInsets:
            expandToParent ? material.EdgeInsets.zero : null,
        initialSelection: value,
        onSelected: enabled ? onSelected : null,
        dropdownMenuEntries: entries,
        textStyle: textStyle,
        inputDecorationTheme: material.InputDecorationTheme(
          isDense: true,
          contentPadding: const material.EdgeInsets.symmetric(vertical: 6),
          enabledBorder: material.UnderlineInputBorder(
            borderSide: material.BorderSide(color: cs.border),
          ),
          focusedBorder: material.UnderlineInputBorder(
            borderSide: material.BorderSide(color: cs.ring, width: 2),
          ),
        ),
        menuStyle: material.MenuStyle(
          backgroundColor: material.WidgetStatePropertyAll(cs.popover),
          surfaceTintColor: material.WidgetStatePropertyAll(cs.popover),
          elevation: const material.WidgetStatePropertyAll(8),
        ),
      ),
    );
  }
}
