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

/// Label + full-width control row for Preferences (uniform dropdown width).
class PreferencesFieldRow extends StatelessWidget {
  const PreferencesFieldRow({
    super.key,
    required this.label,
    required this.control,
    this.hint,
    this.labelWidth = kPreferencesLabelWidth,
  });

  final String label;
  final material.Widget control;
  final String? hint;
  final double labelWidth;

  @override
  material.Widget build(material.BuildContext context) {
    final triggerHeight = QueryaDropdownTokens.scaledTriggerHeight(context);

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Row(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.SizedBox(
              width: labelWidth,
              height: triggerHeight,
              child: material.Align(
                alignment: material.Alignment.centerLeft,
                child: Text(label).small().foreground(),
              ),
            ),
            const material.SizedBox(width: 12),
            material.Expanded(child: control),
          ],
        ),
        if (hint != null) ...[
          const material.SizedBox(height: 4),
          material.Padding(
            padding: material.EdgeInsets.only(left: labelWidth + 12),
            child: PreferencesHint(hint!),
          ),
        ],
      ],
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
    this.expandToParent = true,
    this.enabled = true,
  });

  final T value;
  final List<material.DropdownMenuEntry<T>> entries;
  final material.ValueChanged<T?> onSelected;

  /// Fixed width when [expandToParent] is false.
  final double? width;

  /// Fill parent — use inside [PreferencesFieldRow].
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
