import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_icon_sizes.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Inline error block for connection tree lazy-load failures.
class TreeLoadError extends material.StatelessWidget {
  const TreeLoadError({
    super.key,
    this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.padding = const material.EdgeInsets.only(
      left: 24,
      top: 4,
      bottom: 8,
    ),
    this.detailFontSize = 11,
    this.showTitleRow = false,
  });

  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final material.EdgeInsetsGeometry padding;
  final double detailFontSize;
  final bool showTitleRow;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final destructive = theme.colorScheme.destructive;
    final muted = theme.colorScheme.mutedForeground;

    return material.Padding(
      padding: padding,
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.start,
        mainAxisSize: material.MainAxisSize.min,
        children: [
          if (showTitleRow && title != null)
            material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                material.Icon(
                  QueryaIcons.treeError,
                  size: QueryaIconSizes.treeError,
                  color: destructive,
                ),
                const Gap(6),
                material.Expanded(
                  child: material.Text(
                    title!,
                    maxLines: 2,
                    overflow: material.TextOverflow.ellipsis,
                    style: material.TextStyle(
                      fontSize: 12,
                      color: destructive,
                    ),
                  ),
                ),
              ],
            ),
          if (showTitleRow && title != null) const Gap(6),
          material.SelectableText(
            message,
            style: material.TextStyle(
              fontSize: detailFontSize,
              height: showTitleRow ? 1.35 : null,
              color: showTitleRow ? muted : destructive,
            ),
          ),
          if (onRetry != null) ...[
            const material.SizedBox(height: 6),
            GhostButton(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}
