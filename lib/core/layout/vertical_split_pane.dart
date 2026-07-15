import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/querya_split_handle.dart';
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
class VerticalSplitPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        return ValueListenableBuilder<double>(
          valueListenable: fraction,
          builder: (context, value, panes) {
            final pair = panes! as SplitPanePair;
            final topFlex = (value * 100)
                .round()
                .clamp(
                  (minFraction * 100).round(),
                  (maxFraction * 100).round(),
                )
                .toInt();
            final bottomFlex = 100 - topFlex;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: topFlex, child: pair.top),
                QueryaSplitHandle(
                  key: handleKey,
                  axis: material.Axis.vertical,
                  semanticsLabel: 'Resize query and output panes',
                  semanticsValue: '${(value * 100).round()}% top pane',
                  onDragDelta: (dy) {
                    if (totalHeight <= 0) return;
                    fraction.value = (fraction.value + dy / totalHeight)
                        .clamp(minFraction, maxFraction);
                  },
                ),
                Expanded(flex: bottomFlex, child: pair.bottom),
              ],
            );
          },
          child: SplitPanePair(top: top, bottom: bottom),
        );
      },
    );
  }
}
