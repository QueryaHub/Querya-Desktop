import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/querya_action_menu.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Entries of the diagram's Export menu.
enum ErdExportAction {
  mermaid,
  svg,
  png,
  pdfA4,
  pdfA3,
  dbml,
  copyMermaid,
  copyDbml,
  toggleTheme,
}

/// The toolbar's Export menu.
class ErdExportMenu extends material.StatelessWidget {
  const ErdExportMenu({super.key, required this.onSelected});

  final void Function(ErdExportAction action) onSelected;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    return QueryaActionMenu<ErdExportAction>(
      items: const [
        QueryaActionMenuItem(
          value: ErdExportAction.toggleTheme,
          label: 'Toggle export theme (light / current)',
          icon: material.Icons.palette_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.mermaid,
          label: 'Mermaid (.mmd)',
          icon: material.Icons.account_tree_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.svg,
          label: 'SVG',
          icon: material.Icons.polyline_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.png,
          label: 'PNG',
          icon: material.Icons.image_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.pdfA4,
          label: 'PDF (A4)',
          icon: material.Icons.picture_as_pdf_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.pdfA3,
          label: 'PDF (A3)',
          icon: material.Icons.picture_as_pdf_outlined,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.dbml,
          label: 'DBML (.dbml)',
          icon: material.Icons.code_rounded,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.copyDbml,
          label: 'Copy DBML',
          icon: material.Icons.content_copy_rounded,
        ),
        QueryaActionMenuItem(
          value: ErdExportAction.copyMermaid,
          label: 'Copy Mermaid',
          icon: material.Icons.content_copy_rounded,
        ),
      ],
      onSelected: onSelected,
      child: material.Padding(
        key: const material.ValueKey('erd_export'),
        padding:
            const material.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(material.Icons.file_download_outlined,
                size: 16, color: wb.mutedForeground),
            const material.SizedBox(width: 6),
            const Text('Export'),
            const material.SizedBox(width: 4),
            material.Icon(material.Icons.expand_more_rounded,
                size: 16, color: wb.mutedForeground),
          ],
        ),
      ),
    );
  }
}
