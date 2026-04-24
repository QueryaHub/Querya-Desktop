import 'package:flutter/material.dart' as material;

/// Shared dropdown values for SQL statement timeouts (PostgreSQL / MySQL).
const List<material.DropdownMenuItem<int?>> kSqlStatementTimeoutMenuItems = [
  material.DropdownMenuItem<int?>(
    value: null,
    child: material.Text('No limit'),
  ),
  material.DropdownMenuItem(value: 10, child: material.Text('10 s')),
  material.DropdownMenuItem(value: 30, child: material.Text('30 s')),
  material.DropdownMenuItem(value: 60, child: material.Text('60 s')),
  material.DropdownMenuItem(value: 120, child: material.Text('2 min')),
  material.DropdownMenuItem(value: 300, child: material.Text('5 min')),
  material.DropdownMenuItem(value: 600, child: material.Text('10 min')),
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
    return material.DropdownButton<int?>(
      value: value,
      onChanged: enabled ? onChanged : null,
      items: kSqlStatementTimeoutMenuItems,
    );
  }
}
