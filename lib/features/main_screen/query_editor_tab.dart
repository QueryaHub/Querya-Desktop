import 'package:flutter/material.dart' as material show EdgeInsets, Padding, TextEditingController;
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class QueryEditorTab extends StatelessWidget {
  const QueryEditorTab({
    super.key,
    this.controller,
    this.fontSize = 13,
  });

  /// When null, an internal controller is used (standalone workspace without PG).
  final material.TextEditingController? controller;

  /// Monospace font size in logical pixels.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.all(12),
      child: SqlEditorChrome(
        child: QueryaCodeEditor(
          controller: controller,
          language: QueryaCodeLanguage.sql,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
