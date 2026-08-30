import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Banner displayed when an extension driver process crashes, deadlocks,
/// or disconnects unexpectedly, allowing the user to restart the driver process
/// with a single click and retry the pending action.
class ExtensionDriverRecoveryBanner extends material.StatelessWidget {
  const ExtensionDriverRecoveryBanner({
    super.key,
    required this.onRestart,
    this.isRestarting = false,
    this.customMessage,
  });

  final material.VoidCallback onRestart;
  final bool isRestarting;
  final String? customMessage;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == material.Brightness.dark;

    final bgColor = isDark
        ? theme.colorScheme.destructive.withValues(alpha: 0.12)
        : theme.colorScheme.destructive.withValues(alpha: 0.08);

    final borderColor = theme.colorScheme.destructive.withValues(alpha: 0.35);

    return material.Container(
      margin: const material.EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: material.BoxDecoration(
        color: bgColor,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(color: borderColor),
      ),
      child: material.Row(
        children: [
          material.Icon(
            material.Icons.power_off_rounded,
            size: 20,
            color: theme.colorScheme.destructive,
          ),
          const Gap(12),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                const Text(
                  'Driver Process Terminated or Unresponsive',
                ).semiBold().small(),
                const Gap(2),
                Text(
                  customMessage ??
                      'The background driver process exited or lost communication. '
                          'Restart the driver to restore the connection.',
                ).muted().xSmall(),
              ],
            ),
          ),
          const Gap(12),
          OutlineButton(
            size: ButtonSize.small,
            onPressed: isRestarting ? null : onRestart,
            leading: isRestarting
                ? const material.SizedBox(
                    width: 14,
                    height: 14,
                    child: material.CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const material.Icon(
                    material.Icons.restart_alt_rounded,
                    size: 16,
                  ),
            child: Text(isRestarting ? 'Restarting...' : 'Restart Driver'),
          ),
        ],
      ),
    );
  }
}
