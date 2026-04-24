import 'package:flutter/material.dart' as material
    show EdgeInsets, Padding, TextEditingController, TextStyle;
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/features/main_screen/sql_editor_chrome.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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
    return _QueryEditorBody(controller: controller, fontSize: fontSize);
  }
}

class _QueryEditorBody extends StatefulWidget {
  const _QueryEditorBody({this.controller, required this.fontSize});

  final material.TextEditingController? controller;
  final double fontSize;

  @override
  State<_QueryEditorBody> createState() => _QueryEditorBodyState();
}

class _QueryEditorBodyState extends State<_QueryEditorBody> {
  late material.TextEditingController _owned;
  bool _ownController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = material.TextEditingController();
      _ownController = true;
    } else {
      _owned = widget.controller!;
    }
  }

  @override
  void didUpdateWidget(covariant _QueryEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      setState(() {});
    }
    if (oldWidget.controller != widget.controller) {
      if (_ownController) {
        _owned.dispose();
        _ownController = false;
      }
      if (widget.controller == null) {
        _owned = material.TextEditingController();
        _ownController = true;
      } else {
        _owned = widget.controller!;
      }
    }
  }

  @override
  void dispose() {
    if (_ownController) {
      _owned.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Padding(
      padding: const material.EdgeInsets.all(12),
      child: SqlEditorChrome(
        child: TextField(
          controller: _owned,
          maxLines: null,
          expands: true,
          style: material.TextStyle(
            fontFamily: QueryaTypography.mono,
            fontSize: widget.fontSize,
            color: theme.colorScheme.foreground,
          ),
          placeholder: const Text('-- Enter SQL here…\nSELECT 1;'),
        ),
      ),
    );
  }
}
