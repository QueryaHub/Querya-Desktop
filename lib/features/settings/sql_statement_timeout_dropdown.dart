import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/features/settings/preferences_controls.dart';

/// Shared dropdown values for SQL statement timeouts (PostgreSQL / MySQL).
const List<material.DropdownMenuEntry<int?>> kSqlStatementTimeoutMenuEntries = [
  material.DropdownMenuEntry<int?>(
    value: null,
    label: 'No limit',
  ),
  material.DropdownMenuEntry(value: 10, label: '10 s'),
  material.DropdownMenuEntry(value: 30, label: '30 s'),
  material.DropdownMenuEntry(value: 60, label: '60 s'),
  material.DropdownMenuEntry(value: 120, label: '2 min'),
  material.DropdownMenuEntry(value: 300, label: '5 min'),
  material.DropdownMenuEntry(value: 600, label: '10 min'),
];

/// Statement timeout selector used in SQL toolbars and Preferences.
class SqlStatementTimeoutDropdown extends material.StatelessWidget {
  const SqlStatementTimeoutDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int? value;
  final void Function(int?) onChanged;
  final bool enabled;

  @override
  material.Widget build(material.BuildContext context) {
    return PreferencesDropdownMenu<int?>(
      value: value,
      enabled: enabled,
      onSelected: onChanged,
      entries: kSqlStatementTimeoutMenuEntries,
    );
  }
}
