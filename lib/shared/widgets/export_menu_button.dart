import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/shared/services/data_export_service.dart';
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
    return material.PopupMenuButton<DataExportFormat>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => [
        material.PopupMenuItem(
          value: DataExportFormat.csv,
          child: material.Row(
            children: [
              const material.Icon(
                material.Icons.table_chart_outlined,
                size: 16,
              ),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'CSV (.csv)' : 'Copy as CSV'),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.json,
          child: material.Row(
            children: [
              const material.Icon(
                material.Icons.data_object_rounded,
                size: 16,
              ),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'JSON (.json)' : 'Copy as JSON'),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.markdown,
          child: material.Row(
            children: [
              const material.Icon(material.Icons.code_rounded, size: 16),
              const material.SizedBox(width: 8),
              material.Text(
                isSave ? 'Markdown Table (.md)' : 'Copy as Markdown Table',
              ),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.sqlDump,
          child: material.Row(
            children: [
              const material.Icon(material.Icons.storage_rounded, size: 16),
              const material.SizedBox(width: 8),
              material.Text(
                isSave ? 'SQL INSERT Dump (.sql)' : 'Copy as SQL Dump',
              ),
            ],
          ),
        ),
      ],
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: material.BoxDecoration(
          border: material.Border.all(
            color: Theme.of(context).colorScheme.border,
          ),
          borderRadius: material.BorderRadius.circular(6),
        ),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(
              icon,
              size: 14,
              color: Theme.of(context).colorScheme.foreground,
            ),
            const material.SizedBox(width: 6),
            Text(label).small(),
          ],
        ),
      ),
    );
  }
}
