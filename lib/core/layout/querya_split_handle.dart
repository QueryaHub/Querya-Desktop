import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Accessible split-pane handle that supports mouse dragging and arrow keys.
class QueryaSplitHandle extends material.StatefulWidget {
  const QueryaSplitHandle({
    super.key,
    required this.axis,
    required this.onDragDelta,
    required this.semanticsLabel,
    this.semanticsValue,
    this.keyboardStep = 10,
    this.onDragEnd,
  });

  /// Direction in which the handle moves.
  final material.Axis axis;
  final material.ValueChanged<double> onDragDelta;
  final String semanticsLabel;
  final String? semanticsValue;
  final double keyboardStep;
  final material.VoidCallback? onDragEnd;

  @override
  material.State<QueryaSplitHandle> createState() => _QueryaSplitHandleState();
}

class _QueryaSplitHandleState extends material.State<QueryaSplitHandle> {
  final material.FocusNode _focusNode =
      material.FocusNode(debugLabel: 'Querya split handle');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  material.KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return material.KeyEventResult.ignored;

    final key = event.logicalKey;
    final double? delta = widget.axis == material.Axis.horizontal
        ? switch (key) {
            LogicalKeyboardKey.arrowLeft => -widget.keyboardStep,
            LogicalKeyboardKey.arrowRight => widget.keyboardStep,
            _ => null,
          }
        : switch (key) {
            LogicalKeyboardKey.arrowUp => -widget.keyboardStep,
            LogicalKeyboardKey.arrowDown => widget.keyboardStep,
            _ => null,
          };
    if (delta == null) return material.KeyEventResult.ignored;
    widget.onDragDelta(delta);
    return material.KeyEventResult.handled;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final horizontal = widget.axis == material.Axis.horizontal;
    return material.Focus(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (_, event) => _onKeyEvent(event),
      child: material.Semantics(
        label: widget.semanticsLabel,
        value: widget.semanticsValue,
        increasedValue: widget.semanticsValue,
        decreasedValue: widget.semanticsValue,
        focusable: true,
        focused: _focused,
        onIncrease: () => widget.onDragDelta(widget.keyboardStep),
        onDecrease: () => widget.onDragDelta(-widget.keyboardStep),
        child: material.MouseRegion(
          cursor: horizontal
              ? material.SystemMouseCursors.resizeColumn
              : material.SystemMouseCursors.resizeRow,
          child: material.GestureDetector(
            excludeFromSemantics: true,
            behavior: material.HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            onHorizontalDragUpdate: horizontal
                ? (event) => widget.onDragDelta(event.delta.dx)
                : null,
            onHorizontalDragEnd:
                horizontal ? (_) => widget.onDragEnd?.call() : null,
            onVerticalDragUpdate: horizontal
                ? null
                : (event) => widget.onDragDelta(event.delta.dy),
            onVerticalDragEnd:
                horizontal ? null : (_) => widget.onDragEnd?.call(),
            child: material.Container(
              width: horizontal ? 6 : null,
              height: horizontal ? null : 6,
              decoration: material.BoxDecoration(
                color: colors.border.withValues(alpha: 0.15),
                border: material.Border.all(
                  color: _focused ? colors.ring : material.Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
