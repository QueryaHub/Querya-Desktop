import 'package:flutter/material.dart' as material show ListView, Padding, Container, BoxDecoration, Border, BorderSide, InkWell, Icon, Icons, IconData, EdgeInsets, BorderRadius, CrossAxisAlignment, MainAxisSize, MouseRegion, AnimatedContainer, Curves, SystemMouseCursors, DefaultTextStyle, TextStyle;
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'new_connection_dialog.dart';

/// Left panel: Browser tree (pgAdmin-style). Uses shadcn layout widgets.
class ConnectionsPanel extends StatefulWidget {
  const ConnectionsPanel({super.key});

  @override
  State<ConnectionsPanel> createState() => _ConnectionsPanelState();
}

class _ConnectionsPanelState extends State<ConnectionsPanel> {
  bool _serversExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      decoration: material.BoxDecoration(
        color: theme.colorScheme.background,
        border: material.Border(
          right: material.BorderSide(
            color: theme.colorScheme.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(20, 24, 16, 16),
            child: material.DefaultTextStyle(
              style: material.TextStyle(color: theme.colorScheme.mutedForeground),
              child: Text('Browser').semiBold().small(),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.border.withValues(alpha: 0.3)),
          Expanded(
            child: material.ListView(
              padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                _ExpandableSection(
                  title: 'Servers',
                  icon: material.Icons.dns_rounded,
                  expanded: _serversExpanded,
                  onToggle: () => setState(() => _serversExpanded = !_serversExpanded),
                  contextMenuItems: [
                    MenuButton(
                      onPressed: (menuContext) async {
                        final type = await showNewConnectionDialog(menuContext);
                        if (type != null && mounted) {
                          // TODO: open connection form for selected type
                        }
                      },
                      child: const Text('New connection'),
                    ),
                  ],
                  child: material.Padding(
                    padding: const material.EdgeInsets.only(left: 28, top: 6, bottom: 12),
                    child: _EmptyState(message: 'No connections yet'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.25),
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: material.CrossAxisAlignment.center,
        children: [
          material.Icon(
            material.Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.mutedForeground,
          ),
          const Gap(10),
          Expanded(
            child: Text(message).muted().small(),
          ),
        ],
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.contextMenuItems,
  });

  final String title;
  final material.IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final List<MenuItem>? contextMenuItems;

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = widget.expanded;

    final headerRow = material.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: material.SystemMouseCursors.click,
      child: material.InkWell(
        onTap: widget.onToggle,
        borderRadius: material.BorderRadius.circular(8),
        child: material.AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: material.Curves.easeOut,
          padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: material.BoxDecoration(
            color: _hovered
                ? theme.colorScheme.muted.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: material.BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              material.Icon(
                expanded ? material.Icons.expand_more : material.Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.mutedForeground,
              ),
              const Gap(6),
              material.Icon(
                widget.icon,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const Gap(8),
              Text(widget.title).semiBold().small(),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        if (widget.contextMenuItems != null && widget.contextMenuItems!.isNotEmpty)
          ContextMenu(
            items: widget.contextMenuItems!,
            child: headerRow,
          )
        else
          headerRow,
        if (expanded) widget.child,
      ],
    );
  }
}
