import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class ExportMenuButton extends StatelessWidget {
  const ExportMenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    required this.isSave,
  });

  final String label;
  final material.IconData icon;
  final material.ValueChanged<DataExportFormat> onSelected;
  final bool isSave;

  @override
  Widget build(BuildContext context) {
    return QueryaActionMenu<DataExportFormat>(
      onSelected: onSelected,
      items: [
        QueryaActionMenuItem(
          value: DataExportFormat.csv,
          icon: material.Icons.table_chart_outlined,
          label: isSave ? 'CSV (.csv)' : 'Copy as CSV',
        ),
        QueryaActionMenuItem(
          value: DataExportFormat.json,
          icon: material.Icons.data_object_rounded,
          label: isSave ? 'JSON (.json)' : 'Copy as JSON',
        ),
        QueryaActionMenuItem(
          value: DataExportFormat.markdown,
          icon: material.Icons.code_rounded,
          label: isSave ? 'Markdown Table (.md)' : 'Copy as Markdown Table',
        ),
        QueryaActionMenuItem(
          value: DataExportFormat.sqlDump,
          icon: material.Icons.storage_rounded,
          label: isSave ? 'SQL INSERT Dump (.sql)' : 'Copy as SQL Dump',
        ),
      ],
      child: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Icon(icon, size: 14),
          const material.SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
