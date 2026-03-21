import 'package:flutter/material.dart' as material
    show Padding, EdgeInsets, TextStyle, TextEditingController;
import 'package:querya_desktop/shared/widgets/widgets.dart';

class QueryEditorTab extends StatelessWidget {
  const QueryEditorTab({
    super.key,
    this.controller,
  });

  /// When null, an internal controller is used (standalone workspace without PG).
  final material.TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return _QueryEditorBody(controller: controller);
  }
}

class _QueryEditorBody extends StatefulWidget {
  const _QueryEditorBody({this.controller});

  final material.TextEditingController? controller;

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
    return material.Padding(
      padding: const material.EdgeInsets.all(12),
      child: Card(
        padding: material.EdgeInsets.zero,
        child: TextField(
          controller: _owned,
          maxLines: null,
          expands: true,
          style: const material.TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          placeholder: const Text('-- Enter SQL here…\nSELECT 1;'),
        ),
      ),
    );
  }
}
