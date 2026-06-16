import 'package:flutter/material.dart';
import 'package:refresh_rate/refresh_rate.dart';

import '../ui/panel_widgets.dart';

class ScrollTestPanel extends StatelessWidget {
  const ScrollTestPanel({
    super.key,
    required this.info,
  });

  final DisplayInfo info;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeader(
            eyebrow: 'Exercise',
            title: 'Scroll Test',
            subtitle:
                'Use this list to generate sustained motion and compare the on-screen experience against the live frame budget.',
          ),
          const SizedBox(height: 12),
          Container(
            height: 340,
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E0E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: 30,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final laneColor = index.isEven
                    ? const Color(0xFF00F0FF)
                    : const Color(0xFF36FF8B);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: laneColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: laneColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trace sample ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target ${(info.maxRate > 0 ? info.maxRate : info.currentRate).toStringAsFixed(0)} Hz • verify pacing under continuous scroll.',
                              style: const TextStyle(
                                color: Color(0xFFB9CACB),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(index + 1) * 8} ms',
                        style: const TextStyle(
                          color: Color(0xFFB9CACB),
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
