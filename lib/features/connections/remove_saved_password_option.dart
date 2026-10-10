import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// "Remove the saved password" in an edit form (#1311).
///
/// A blank password field means *keep the saved one*, and the form never shows
/// it, so without this a saved password could not be taken away (a database
/// that moved to trust authentication, a password that must not stay on disk).
class RemoveSavedPasswordOption extends material.StatelessWidget {
  const RemoveSavedPasswordOption({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final material.ValueChanged<bool> onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.only(top: 6),
      child: material.Row(
        children: [
          material.Checkbox(
            key: const material.ValueKey('remove_saved_password'),
            value: value,
            onChanged: (v) => onChanged(v ?? false),
          ),
          const Gap(8),
          material.Flexible(
            child: const Text('Remove the saved password').small(),
          ),
        ],
      ),
    );
  }
}
