import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A compact, keyboard-operable tab strip using Querya's motion and theme.
class QueryaTabStrip extends material.StatefulWidget {
  const QueryaTabStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(labels.length > 0);

  final List<String> labels;
  final int selectedIndex;
  final material.ValueChanged<int> onSelected;

  @override
  material.State<QueryaTabStrip> createState() => _QueryaTabStripState();
}

class _QueryaTabStripState extends material.State<QueryaTabStrip> {
  late List<material.FocusNode> _focusNodes;
  late List<bool> _focused;

  @override
  void initState() {
    super.initState();
    _createFocusState();
  }

  @override
  void didUpdateWidget(covariant QueryaTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _disposeFocusNodes();
      _createFocusState();
    }
  }

  void _createFocusState() {
    _focusNodes = List.generate(
      widget.labels.length,
      (index) =>
          material.FocusNode(debugLabel: 'Querya tab ${widget.labels[index]}'),
    );
    _focused = List.filled(widget.labels.length, false);
  }

  void _disposeFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    super.dispose();
  }

  void _selectAndFocus(int index) {
    widget.onSelected(index);
    _focusNodes[index].requestFocus();
  }

  material.KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return material.KeyEventResult.ignored;

    final last = widget.labels.length - 1;
    final int? target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => index == 0 ? last : index - 1,
      LogicalKeyboardKey.arrowRight => index == last ? 0 : index + 1,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => last,
      _ => null,
    };
    if (target == null) return material.KeyEventResult.ignored;
    _selectAndFocus(target);
    return material.KeyEventResult.handled;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return material.Row(
      mainAxisSize: material.MainAxisSize.min,
      children: List.generate(widget.labels.length, (index) {
        final selected = widget.selectedIndex == index;
        final focused = _focused[index];
        final label = widget.labels[index];
        return material.Padding(
          padding: material.EdgeInsets.only(left: index == 0 ? 0 : 6),
          child: material.Focus(
            focusNode: _focusNodes[index],
            onFocusChange: (value) => setState(() => _focused[index] = value),
            onKeyEvent: (_, event) => _onKeyEvent(index, event),
            child: material.Semantics(
              button: true,
              selected: selected,
              label: label,
              onTap: () => _selectAndFocus(index),
              child: material.ExcludeSemantics(
                child: material.MouseRegion(
                  cursor: material.SystemMouseCursors.click,
                  child: material.GestureDetector(
                    excludeFromSemantics: true,
                    behavior: material.HitTestBehavior.opaque,
                    onTap: () => _selectAndFocus(index),
                    child: material.AnimatedContainer(
                      key: material.ValueKey('querya_tab_$label'),
                      duration: context.motionDuration(QueryaMotion.fast),
                      curve: context.motionCurve(QueryaMotion.enter),
                      padding: const material.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: material.BoxDecoration(
                        color: selected
                            ? colors.background
                            : material.Colors.transparent,
                        borderRadius: material.BorderRadius.circular(6),
                        border: material.Border.all(
                          color: focused
                              ? colors.ring
                              : material.Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Text(label).small().semiBold()
                          : Text(label).small().muted(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
