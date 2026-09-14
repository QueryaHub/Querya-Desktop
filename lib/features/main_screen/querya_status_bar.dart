import 'dart:io' show Platform;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Obsidian/IDE standard bottom status bar.
///
/// Displays:
/// - Active connection status, protocol, host, and read-only lock.
/// - Background operation activity.
/// - Execution time / latency, row/column counts, and encoding.
class QueryaStatusBar extends material.StatelessWidget {
  const QueryaStatusBar({
    super.key,
    this.activeConnection,
    this.isReadOnly = false,
    this.isSidebarVisible = true,
    this.onToggleSidebar,
    this.statusMessage,
    this.isBusy = false,
    this.rowCount,
    this.columnCount,
    this.lastQueryDuration,
    this.onOpenPreferences,
  });

  final ConnectionRow? activeConnection;
  final bool isReadOnly;
  final bool isSidebarVisible;
  final material.VoidCallback? onToggleSidebar;
  final String? statusMessage;
  final bool isBusy;
  final int? rowCount;
  final int? columnCount;
  final Duration? lastQueryDuration;
  final material.VoidCallback? onOpenPreferences;

  @override
  material.Widget build(material.BuildContext context) {
    final wb = context.workbench;
    final theme = Theme.of(context);
    final isMac = Platform.isMacOS;

    return material.Container(
      height: context.scaled(26),
      decoration: material.BoxDecoration(
        color: wb.canvas,
        border: material.Border(
          top: material.BorderSide(
            color: wb.borderSubtle.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
      ),
      padding: const material.EdgeInsets.symmetric(horizontal: 10),
      child: material.Row(
        children: [
          // 1. Sidebar toggle quick button
          if (onToggleSidebar != null) ...[
            material.Tooltip(
              message: 'Toggle Sidebar (${isMac ? "Cmd+B" : "Ctrl+B"})',
              child: material.InkWell(
                onTap: onToggleSidebar,
                borderRadius: material.BorderRadius.circular(3),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(3),
                  child: material.Icon(
                    isSidebarVisible
                        ? material.Icons.view_sidebar_rounded
                        : material.Icons.view_sidebar_outlined,
                    size: 13,
                    color: isSidebarVisible
                        ? wb.accent
                        : wb.mutedForeground,
                  ),
                ),
              ),
            ),
            const Gap(8),
            _vDivider(wb.borderSubtle),
            const Gap(8),
          ],

          // 2. Active connection status & dot & central messages
          material.Expanded(
            child: material.Row(
              children: [
                material.Container(
                  width: 7,
                  height: 7,
                  decoration: material.BoxDecoration(
                    shape: material.BoxShape.circle,
                    color: activeConnection != null ? wb.success : wb.mutedForeground.withValues(alpha: 0.4),
                  ),
                ),
                const Gap(6),
                if (activeConnection != null) ...[
                  material.Icon(
                    QueryaIcons.connectionIcon(activeConnection!.type),
                    size: 13,
                    color: wb.accent,
                  ),
                  const Gap(5),
                  material.Flexible(
                    flex: 2,
                    child: material.Text(
                      activeConnection!.name,
                      overflow: material.TextOverflow.ellipsis,
                      style: material.TextStyle(
                        fontSize: 11,
                        fontWeight: material.FontWeight.w500,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  if (activeConnection!.host != null) ...[
                    const Gap(4),
                    material.Flexible(
                      flex: 3,
                      child: material.Text(
                        '(${activeConnection!.host}:${activeConnection!.port ?? ""})',
                        overflow: material.TextOverflow.ellipsis,
                        style: material.TextStyle(
                          fontSize: 10,
                          fontFamily: QueryaTypography.mono,
                          color: wb.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                  if (isReadOnly) ...[
                    const Gap(6),
                    material.Tooltip(
                      message: 'Read-only connection mode active',
                      child: material.Row(
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          material.Icon(
                            material.Icons.lock_outline_rounded,
                            size: 12,
                            color: wb.warning,
                          ),
                          const Gap(2),
                          material.Text(
                            'Read-only',
                            style: material.TextStyle(
                              fontSize: 10,
                              fontWeight: material.FontWeight.w600,
                              color: wb.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  material.Text(
                    'No connection',
                    style: material.TextStyle(
                      fontSize: 11,
                      color: wb.mutedForeground,
                    ),
                  ),
                ],

                if (isBusy) ...[
                  const Gap(10),
                  material.SizedBox(
                    width: 10,
                    height: 10,
                    child: material.CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: wb.accent,
                    ),
                  ),
                ],
                if (statusMessage != null && statusMessage!.isNotEmpty) ...[
                  const Gap(8),
                  material.Flexible(
                    flex: 4,
                    child: material.Text(
                      statusMessage!,
                      overflow: material.TextOverflow.ellipsis,
                      style: material.TextStyle(
                        fontSize: 11,
                        color: wb.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Gap(12),

          // 4. Right status metrics: execution time, rows/cols, encoding
          if (lastQueryDuration != null) ...[
            material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(
                  material.Icons.timer_outlined,
                  size: 12,
                  color: wb.mutedForeground,
                ),
                const Gap(3),
                material.Text(
                  '${lastQueryDuration!.inMilliseconds} ms',
                  style: material.TextStyle(
                    fontSize: 10,
                    fontFamily: QueryaTypography.mono,
                    color: wb.mutedForeground,
                  ),
                ),
              ],
            ),
            const Gap(8),
            _vDivider(wb.borderSubtle),
            const Gap(8),
          ],

          if (rowCount != null) ...[
            material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(
                  material.Icons.table_rows_rounded,
                  size: 12,
                  color: wb.mutedForeground,
                ),
                const Gap(3),
                material.Text(
                  '$rowCount rows${columnCount != null ? ", $columnCount cols" : ""}',
                  style: material.TextStyle(
                    fontSize: 10,
                    fontFamily: QueryaTypography.mono,
                    color: wb.mutedForeground,
                  ),
                ),
              ],
            ),
            const Gap(8),
            _vDivider(wb.borderSubtle),
            const Gap(8),
          ],

          // Encoding tag
          material.Text(
            'UTF-8',
            style: material.TextStyle(
              fontSize: 10,
              fontFamily: QueryaTypography.mono,
              color: wb.mutedForeground.withValues(alpha: 0.7),
            ),
          ),

          if (onOpenPreferences != null) ...[
            const Gap(8),
            _vDivider(wb.borderSubtle),
            const Gap(6),
            material.Tooltip(
              message: 'Preferences (${isMac ? "Cmd+," : "Ctrl+,"})',
              child: material.InkWell(
                onTap: onOpenPreferences,
                borderRadius: material.BorderRadius.circular(3),
                child: material.Padding(
                  padding: const material.EdgeInsets.all(3),
                  child: material.Icon(
                    material.Icons.tune_rounded,
                    size: 13,
                    color: wb.mutedForeground,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  material.Widget _vDivider(material.Color color) {
    return material.Container(
      width: 1,
      height: 12,
      color: color.withValues(alpha: 0.25),
    );
  }
}
