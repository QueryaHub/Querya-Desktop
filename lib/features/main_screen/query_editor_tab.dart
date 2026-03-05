import 'package:flutter/material.dart' as material show Padding, EdgeInsets, TextStyle;
import 'package:querya_desktop/shared/widgets/widgets.dart';

class QueryEditorTab extends StatelessWidget {
  const QueryEditorTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const material.Padding(
      padding: material.EdgeInsets.all(12),
      child: Card(
        padding: material.EdgeInsets.zero,
        child: TextField(
          maxLines: null,
          expands: true,
          style: material.TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          placeholder: Text('-- Enter SQL here…\nSELECT 1;'),
        ),
      ),
    );
  }
}
