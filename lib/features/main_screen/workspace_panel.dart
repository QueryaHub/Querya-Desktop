import 'package:flutter/material.dart' as material show Container, EdgeInsets, BoxDecoration, GestureDetector, Padding, BorderRadius, Spacer, Center, CrossAxisAlignment, Icon, Icons, MouseRegion, AnimatedContainer, AnimatedScale, Curves, SystemMouseCursors, LayoutBuilder, HitTestBehavior, SizedBox;
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'mongo_databases_view.dart';
import 'query_editor_tab.dart';
import 'redis_view.dart';
import 'results_tab.dart';

/// Main workspace: top = Query Editor / Query History, bottom = Data Output / Messages (pgAdmin-style). Uses shadcn layout.
class WorkspacePanel extends StatefulWidget {
  const WorkspacePanel({
    super.key,
    this.activeConnection,
  });

  /// Currently selected connection from the sidebar.
  final ConnectionRow? activeConnection;

  @override
  State<WorkspacePanel> createState() => _WorkspacePanelState();
}

class _WorkspacePanelState extends State<WorkspacePanel> {
  int _editorTabIndex = 0;
  int _outputTabIndex = 0;
  double _topFraction = 0.7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If a MongoDB connection is selected, show the databases view
    if (widget.activeConnection != null &&
        widget.activeConnection!.type == 'mongodb') {
      return MongoDatabasesView(
        key: ValueKey(widget.activeConnection!.id),
        connectionRow: widget.activeConnection!,
      );
    }

    // If a Redis connection is selected, show the Redis view (wrapped so it gets bounded constraints)
    if (widget.activeConnection != null &&
        widget.activeConnection!.type == 'redis') {
      return material.Container(
        color: theme.colorScheme.background,
        child: material.SizedBox.expand(
          child: RedisView(
            key: ValueKey(widget.activeConnection!.id),
            connectionRow: widget.activeConnection!,
          ),
        ),
      );
    }

    final topFlex = (_topFraction * 100).round().clamp(20, 80);
    final bottomFlex = 100 - topFlex;

    return material.Container(
      color: theme.colorScheme.background,
      child: material.LayoutBuilder(
        builder: (context, constraints) {
          final totalHeight = constraints.maxHeight;
          return Column(
            children: [
              Expanded(
                flex: topFlex,
                child: Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    _SectionBar(
                      title: 'Query',
                      tabs: const ['Query Editor', 'Query History'],
                      index: _editorTabIndex,
                      onTabChanged: (v) => setState(() => _editorTabIndex = v),
                      trailing: const _RunButton(),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: IndexedStack(
                        index: _editorTabIndex,
                        children: const [
                          QueryEditorTab(),
                          _PlaceholderTab(message: 'Query history'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _HorizontalResizeHandle(
                totalHeight: totalHeight,
                onDrag: (dy) {
                  if (totalHeight <= 0) return;
                  setState(() {
                    _topFraction = (_topFraction + dy / totalHeight).clamp(0.2, 0.8);
                  });
                },
              ),
              Expanded(
                flex: bottomFlex,
                child: Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: [
                    _SectionBar(
                      title: 'Output',
                      tabs: const ['Data Output', 'Messages', 'Notifications'],
                      index: _outputTabIndex,
                      onTabChanged: (v) => setState(() => _outputTabIndex = v),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: IndexedStack(
                        index: _outputTabIndex,
                        children: const [
                          ResultsTab(),
                          _PlaceholderTab(message: 'Messages'),
                          _PlaceholderTab(message: 'Notifications'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HorizontalResizeHandle extends StatelessWidget {
  const _HorizontalResizeHandle({
    required this.totalHeight,
    required this.onDrag,
  });

  final double totalHeight;
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

class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.title,
    required this.tabs,
    required this.index,
    required this.onTabChanged,
    this.trailing,
  });

  final String title;
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTabChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return material.Container(
      height: 44,
      padding: const material.EdgeInsets.symmetric(horizontal: 12),
      decoration: material.BoxDecoration(
        color: theme.colorScheme.muted.withValues(alpha: 0.6),
      ),
      child: Row(
        children: [
          material.Padding(
            padding: const material.EdgeInsets.only(right: 16),
            child: Text(title).semiBold().small(),
          ),
          ...List.generate(tabs.length, (i) {
            return _TabButton(
              label: tabs[i],
              selected: index == i,
              onTap: () => onTabChanged(i),
              theme: theme,
            );
          }),
          const material.Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isSelected = widget.selected;
    final bgColor = isSelected
        ? theme.colorScheme.background
        : _hovered
            ? theme.colorScheme.muted.withValues(alpha: 0.5)
            : Colors.transparent;

    return material.Padding(
      padding: const material.EdgeInsets.only(right: 4),
      child: material.MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: material.SystemMouseCursors.click,
        child: material.GestureDetector(
          onTap: widget.onTap,
          child: material.AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: material.Curves.easeOut,
            padding: const material.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: material.BoxDecoration(
              color: bgColor,
              borderRadius: material.BorderRadius.circular(6),
            ),
            child: isSelected
                ? Text(widget.label).semiBold().small()
                : Text(widget.label).muted().small(),
          ),
        ),
      ),
    );
  }
}

class _RunButton extends StatefulWidget {
  const _RunButton();

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return material.MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: material.SystemMouseCursors.click,
      child: material.AnimatedScale(
        scale: _hovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: material.Curves.easeOut,
        child: OutlineButton(
          onPressed: () {},
          leading: const material.Icon(material.Icons.play_arrow, size: 18),
          child: const Text('Execute/Refresh (F5)'),
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return material.Center(child: Text(message).muted());
  }
}
