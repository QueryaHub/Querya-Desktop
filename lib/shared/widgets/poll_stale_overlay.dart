import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:querya_desktop/core/motion/polling_controller.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';

/// Shows [child] with a small "out of date" note in the top-right corner while
/// the latest poll failed, so a dashboard that kept its last good numbers does
/// not look live.
class PollStaleOverlay extends StatelessWidget {
  const PollStaleOverlay({super.key, required this.status, required this.child});

  final ValueListenable<PollStatus> status;
  final Widget child;

  static String message(PollStatus s) {
    final at = s.lastSuccess;
    if (at == null) return 'Updates failed';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Updates failed · showing ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 8,
          right: 16,
          child: ValueListenableBuilder<PollStatus>(
            valueListenable: status,
            builder: (context, s, _) {
              if (!s.isStale) return const SizedBox.shrink();
              final colors = context.colors;
              return Tooltip(
                message: '${s.lastError}',
                child: DecoratedBox(
                  key: const ValueKey('poll_stale_hint'),
                  decoration: BoxDecoration(
                    color: colors.destructive.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      message(s),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.destructive,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
