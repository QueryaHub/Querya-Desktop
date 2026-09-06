import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/features/workspace/grid_data_type_validator.dart';
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
    this.dataTypeName,
    this.onOpenInspector,
  });

  final String initialValue;
  final double width;
  final double height;
  final String? dataTypeName;
  final void Function(
    String value, {
    bool moveNextCol,
    bool movePrevCol,
    bool moveNextRow,
    bool movePrevRow,
  }) onCommit;
  final material.VoidCallback onCancel;
  final material.VoidCallback? onOpenInspector;

  @override
  material.State<GridCellEditor> createState() => _GridCellEditorState();
}

class _GridCellEditorState extends material.State<GridCellEditor> {
  late final material.TextEditingController _controller;
  final _focusNode = material.FocusNode();
  String? _validationError;

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

    _validate();
    _controller.addListener(_validate);
  }

  void _validate() {
    final error = GridDataTypeValidator.validate(
      _controller.text,
      dataTypeName: widget.dataTypeName,
    );
    if (error != _validationError) {
      setState(() {
        _validationError = error;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_validate);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isControl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Alt+N / Ctrl+Alt+N -> Set NULL
    if (event.logicalKey == LogicalKeyboardKey.keyN && (isAlt || (isControl && isAlt))) {
      widget.onCommit('NULL');
      return;
    }

    // Alt+Enter or Ctrl+Enter -> Open Inspector
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        (isAlt || isControl)) {
      widget.onOpenInspector?.call();
      return;
    }

    // Enter / Shift+Enter -> Commit and navigate row
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isShift) {
        widget.onCommit(_controller.text, movePrevRow: true);
      } else {
        widget.onCommit(_controller.text, moveNextRow: true);
      }
      return;
    }

    // Tab / Shift+Tab -> Commit and navigate col
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (isShift) {
        widget.onCommit(_controller.text, movePrevCol: true);
      } else {
        widget.onCommit(_controller.text, moveNextCol: true);
      }
      return;
    }

    // Escape -> Cancel
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return;
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = _validationError != null;

    return material.AnimatedContainer(
      duration: context.motionDuration(QueryaMotion.fast),
      curve: context.motionCurve(QueryaMotion.enter),
      width: widget.width,
      height: widget.height,
      decoration: material.BoxDecoration(
        color: cs.card,
        border: material.Border.all(
          color: hasError ? material.Colors.red.shade500 : cs.primary,
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
          if (hasError)
            material.Tooltip(
              message: _validationError!,
              child: material.Padding(
                padding: const material.EdgeInsets.only(left: 4),
                child: material.Icon(
                  material.Icons.error_outline_rounded,
                  size: 14,
                  color: material.Colors.red.shade500,
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
