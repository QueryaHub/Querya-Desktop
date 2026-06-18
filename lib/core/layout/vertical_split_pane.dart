import 'package:flutter/material.dart' as material;
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

class _VerticalSplitPaneState extends State<VerticalSplitPane> {
  final GlobalKey _columnKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.fraction,
      builder: (context, value, panes) {
        final pair = panes! as SplitPanePair;
        final topFlex = (value * 100).round().clamp(20, 80).toInt();
        final bottomFlex = 100 - topFlex;
        return Column(
          key: _columnKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: topFlex, child: pair.top),
            _VerticalSplitHandle(
              key: widget.handleKey,
              onDrag: (dy) {
                final box = _columnKey.currentContext?.findRenderObject() as RenderBox?;
                final totalHeight = box?.size.height ?? 0;
                if (totalHeight <= 0) return;
                widget.fraction.value = (widget.fraction.value + dy / totalHeight)
                    .clamp(widget.minFraction, widget.maxFraction);
              },
            ),
            Expanded(flex: bottomFlex, child: pair.bottom),
          ],
        );
      },
      child: SplitPanePair(top: widget.top, bottom: widget.bottom),
    );
  }
}

class _VerticalSplitHandle extends StatelessWidget {
  const _VerticalSplitHandle({super.key, required this.onDrag});

  final void Function(double dy) onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.resizeRow,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onVerticalDragUpdate: (e) => onDrag(e.delta.dy),
        child: material.Container(
          height: 6,
          color: theme.border.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}
