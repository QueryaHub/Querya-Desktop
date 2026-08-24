import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Active inline editor widget for a data grid cell.
class GridCellEditor extends material.StatefulWidget {
  const GridCellEditor({
    super.key,
    required this.initialValue,
    required this.width,
    required this.height,
    required this.onCommit,
    required this.onCancel,
    this.onOpenInspector,
  });

  final String initialValue;
  final double width;
  final double height;
  final void Function(
    String value, {
    bool moveNextCol,
    bool movePrevCol,
    bool moveNextRow,
  }) onCommit;
  final material.VoidCallback onCancel;
  final material.VoidCallback? onOpenInspector;

  @override
  material.State<GridCellEditor> createState() => _GridCellEditorState();
}

class _GridCellEditorState extends material.State<GridCellEditor> {
  late final material.TextEditingController _controller;
  final _focusNode = material.FocusNode();

  @override
  void initState() {
    super.initState();
    final isNull = widget.initialValue == 'NULL';
    _controller = material.TextEditingController(
      text: isNull ? '' : widget.initialValue,
    );
    _controller.selection = material.TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (event.logicalKey == LogicalKeyboardKey.keyN && isAlt) {
      widget.onCommit('NULL');
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onCommit(_controller.text, moveNextRow: true);
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (isShift) {
        widget.onCommit(_controller.text, movePrevCol: true);
      } else {
        widget.onCommit(_controller.text, moveNextCol: true);
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return;
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Container(
      width: widget.width,
      height: widget.height,
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border.all(
          color: cs.primary,
          width: 1.5,
        ),
      ),
      padding: const material.EdgeInsets.symmetric(horizontal: 6),
      alignment: material.Alignment.centerLeft,
      child: material.Row(
        children: [
          material.Expanded(
            child: material.KeyboardListener(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              autofocus: true,
              child: material.TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 1,
                style: const material.TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: const material.InputDecoration(
                  border: material.InputBorder.none,
                  isDense: true,
                  contentPadding: material.EdgeInsets.zero,
                ),
                onSubmitted: (value) {
                  widget.onCommit(value, moveNextRow: true);
                },
              ),
            ),
          ),
          if (widget.onOpenInspector != null)
            material.MouseRegion(
              cursor: material.SystemMouseCursors.click,
              child: material.GestureDetector(
                onTap: () {
                  widget.onOpenInspector!();
                },
                child: material.Padding(
                  padding: const material.EdgeInsets.only(left: 4),
                  child: material.Icon(
                    material.Icons.open_in_full_rounded,
                    size: 13,
                    color: cs.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
