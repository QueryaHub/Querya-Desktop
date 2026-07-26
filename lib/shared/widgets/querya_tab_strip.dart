import 'package:flutter/material.dart' as material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:querya_desktop/core/motion/querya_spring_controller.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// A compact, keyboard-operable tab strip using Querya's motion and theme.
///
/// Selection uses a sliding pill indicator (spring when [QueryaSpring.springsEnabled])
/// so tab changes feel continuous / redirectable.
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

class _QueryaTabStripState extends material.State<QueryaTabStrip>
    with material.TickerProviderStateMixin {
  late List<material.FocusNode> _focusNodes;
  late List<bool> _focused;
  late List<material.GlobalKey> _tabKeys;
  final material.GlobalKey _stripKey = material.GlobalKey();

  late final QueryaSpringController _indicatorLeft;
  late final QueryaSpringController _indicatorWidth;
  var _indicatorReady = false;
  var _layoutScheduled = false;

  @override
  void initState() {
    super.initState();
    _indicatorLeft = QueryaSpringController(vsync: this);
    _indicatorWidth = QueryaSpringController(vsync: this);
    _createFocusState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final springs = QueryaSpring.springsEnabled(context);
    _indicatorLeft.useSprings = springs;
    _indicatorWidth.useSprings = springs;
  }

  @override
  void didUpdateWidget(covariant QueryaTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _disposeFocusNodes();
      _createFocusState();
      _indicatorReady = false;
    }
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.labels.length != widget.labels.length ||
        !_listEquals(oldWidget.labels, widget.labels)) {
      _scheduleIndicatorSync();
    }
  }

  void _createFocusState() {
    _focusNodes = List.generate(
      widget.labels.length,
      (index) =>
          material.FocusNode(debugLabel: 'Querya tab ${widget.labels[index]}'),
    );
    _focused = List.filled(widget.labels.length, false);
    _tabKeys = List.generate(widget.labels.length, (_) => material.GlobalKey());
  }

  void _disposeFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
  }

  @override
  void dispose() {
    _indicatorLeft.dispose();
    _indicatorWidth.dispose();
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

  void _scheduleIndicatorSync() {
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      _syncIndicator();
    });
  }

  void _syncIndicator() {
    final safeIndex = widget.selectedIndex.clamp(0, widget.labels.length - 1);
    final tabContext = _tabKeys[safeIndex].currentContext;
    final stripContext = _stripKey.currentContext;
    if (tabContext == null || stripContext == null) return;

    final tabBox = tabContext.findRenderObject();
    final stripBox = stripContext.findRenderObject();
    if (tabBox is! material.RenderBox || stripBox is! material.RenderBox) {
      return;
    }
    if (!tabBox.hasSize || !stripBox.hasSize) return;

    final offset =
        tabBox.localToGlobal(material.Offset.zero, ancestor: stripBox);
    final width = tabBox.size.width;

    if (!_indicatorReady) {
      _indicatorLeft.jumpTo(offset.dx);
      _indicatorWidth.jumpTo(width);
      setState(() => _indicatorReady = true);
      return;
    }

    _indicatorLeft.animateTo(offset.dx);
    _indicatorWidth.animateTo(width);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _scheduleIndicatorSync();

    return material.KeyedSubtree(
      key: _stripKey,
      child: material.ListenableBuilder(
        listenable: material.Listenable.merge([
          _indicatorLeft,
          _indicatorWidth,
        ]),
        builder: (context, _) {
          return material.Stack(
            alignment: material.Alignment.centerLeft,
            children: [
              if (_indicatorReady && _indicatorWidth.value > 0)
                material.Positioned(
                  key: const material.ValueKey('querya_tab_indicator'),
                  left: _indicatorLeft.value,
                  width: _indicatorWidth.value,
                  top: 0,
                  bottom: 0,
                  child: material.IgnorePointer(
                    child: material.DecoratedBox(
                      decoration: material.BoxDecoration(
                        color: colors.background,
                        borderRadius: material.BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: List.generate(widget.labels.length, (index) {
                  final selected = widget.selectedIndex == index;
                  final focused = _focused[index];
                  final label = widget.labels[index];
                  return material.Padding(
                    padding:
                        material.EdgeInsets.only(left: index == 0 ? 0 : 6),
                    child: material.KeyedSubtree(
                      key: _tabKeys[index],
                      child: material.Focus(
                        focusNode: _focusNodes[index],
                        onFocusChange: (value) =>
                            setState(() => _focused[index] = value),
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
                                  duration: context
                                      .motionDuration(QueryaMotion.fast),
                                  curve: context
                                      .motionCurve(QueryaMotion.enter),
                                  padding: const material.EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: material.BoxDecoration(
                                    color: material.Colors.transparent,
                                    borderRadius:
                                        material.BorderRadius.circular(6),
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
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
