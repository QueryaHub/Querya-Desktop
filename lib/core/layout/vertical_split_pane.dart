import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/querya_drag_settle.dart';
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
import 'package:querya_desktop/core/motion/querya_spring.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Holds top/bottom panes for [VerticalSplitPane] [ValueListenableBuilder.child].
class SplitPanePair extends StatelessWidget {
  const SplitPanePair({super.key, required this.top, required this.bottom});

  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) => top;
}

/// Vertical split whose drag updates [fraction] without rebuilding [top]/[bottom].
///
/// Mid-drag is 1:1; on release a spring settle uses drag velocity when springs
/// are enabled.
class VerticalSplitPane extends StatefulWidget {
  const VerticalSplitPane({
    super.key,
    required this.fraction,
    required this.top,
    required this.bottom,
    this.minFraction = 0.2,
    this.maxFraction = 0.8,
    this.handleKey,
  });

  final ValueNotifier<double> fraction;
  final Widget top;
  final Widget bottom;
  final double minFraction;
  final double maxFraction;
  final Key? handleKey;

  @override
  State<VerticalSplitPane> createState() => _VerticalSplitPaneState();
}

class _VerticalSplitPaneState extends State<VerticalSplitPane>
    with SingleTickerProviderStateMixin {
  late final QueryaDragSettleController _settle;
  var _syncingFromSettle = false;

  @override
  void initState() {
    super.initState();
    _settle = QueryaDragSettleController(
      vsync: this,
      value: widget.fraction.value,
    );
    _settle.addListener(_onSettleChanged);
    widget.fraction.addListener(_onFractionExternal);
  }

  @override
  void didUpdateWidget(covariant VerticalSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fraction != widget.fraction) {
      oldWidget.fraction.removeListener(_onFractionExternal);
      widget.fraction.addListener(_onFractionExternal);
      _settle.jumpTo(widget.fraction.value);
    }
  }

  @override
  void dispose() {
    widget.fraction.removeListener(_onFractionExternal);
    _settle.removeListener(_onSettleChanged);
    _settle.dispose();
    super.dispose();
  }

  void _onFractionExternal() {
    if (_syncingFromSettle) return;
    if ((_settle.value - widget.fraction.value).abs() > 0.0001) {
      _settle.jumpTo(widget.fraction.value);
    }
  }

  void _onSettleChanged() {
    _syncingFromSettle = true;
    widget.fraction.value = _settle.value
        .clamp(widget.minFraction, widget.maxFraction)
        .toDouble();
    _syncingFromSettle = false;
  }

  double _clamp(double raw) =>
      raw.clamp(widget.minFraction, widget.maxFraction).toDouble();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return ValueListenableBuilder<double>(
          valueListenable: widget.fraction,
          builder: (context, value, panes) {
            final pair = panes! as SplitPanePair;
            final topFlex = (value * 100)
                .round()
                .clamp(
                  (widget.minFraction * 100).round(),
                  (widget.maxFraction * 100).round(),
                )
                .toInt();
            final bottomFlex = 100 - topFlex;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: topFlex,
                  child: material.RepaintBoundary(child: pair.top),
                ),
                QueryaSplitHandle(
                  key: widget.handleKey,
                  axis: material.Axis.vertical,
                  semanticsLabel: 'Resize query and output panes',
                  semanticsValue: '${(value * 100).round()}% top pane',
                  onDragDelta: (dy) {
                    if (totalHeight <= 0) return;
                    _settle.dragTo(
                      _clamp(_settle.value + dy / totalHeight),
                    );
                  },
                  onDragEnd: (details) {
                    if (totalHeight <= 0) return;
                    final velocity =
                        details.primaryVelocity ??
                            details.velocity.pixelsPerSecond.dy;
                    _settle.settle(
                      velocity: velocity / totalHeight,
                      useSprings: QueryaSpring.springsEnabled(context),
                    );
                  },
                ),
                Expanded(
                  flex: bottomFlex,
                  child: material.RepaintBoundary(child: pair.bottom),
                ),
              ],
            );
          },
          child: SplitPanePair(top: widget.top, bottom: widget.bottom),
        );
      },
    );
  }
}
