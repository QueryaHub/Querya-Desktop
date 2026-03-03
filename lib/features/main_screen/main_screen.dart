import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart' as material show Scaffold, Container, MainAxisSize, GestureDetector, MouseRegion, SystemMouseCursors, HitTestBehavior;
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

import 'connections_panel.dart';
import 'workspace_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _minLeftWidth = 180;
  static const double _maxLeftWidth = 500;
  double _leftPanelWidth = 260;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.dark.colorScheme;
    return material.Scaffold(
      backgroundColor: theme.background,
      body: Theme(
        data: AppTheme.dark,
        child: WindowBorder(
          color: theme.border.withValues(alpha: 0.6),
          width: 1,
          child: Column(
            children: [
              _CustomTitleBar(theme: theme),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: _leftPanelWidth,
                      child: const ConnectionsPanel(),
                    ),
                    _VerticalResizeHandle(
                      onDrag: (dx) {
                        setState(() {
                          _leftPanelWidth = (_leftPanelWidth + dx)
                              .clamp(_minLeftWidth, _maxLeftWidth);
                        });
                      },
                    ),
                    const Expanded(child: WorkspacePanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalResizeHandle extends StatelessWidget {
  const _VerticalResizeHandle({required this.onDrag});

  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.resizeColumn,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onHorizontalDragUpdate: (e) => onDrag(e.delta.dx),
        child: material.Container(
          width: 6,
          color: theme.border.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  const _CustomTitleBar({required this.theme});

  final ColorScheme theme;

  @override
  Widget build(BuildContext context) {
    final c = theme;
    final buttonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: c.muted.withValues(alpha: 0.5),
      mouseDown: c.muted.withValues(alpha: 0.7),
      iconMouseOver: c.foreground,
      iconMouseDown: c.foreground,
    );
    final closeButtonColors = WindowButtonColors(
      iconNormal: c.mutedForeground,
      mouseOver: const Color(0xFFE53935),
      mouseDown: const Color(0xFFB71C1C),
      iconMouseOver: const Color(0xFFFFFFFF),
      iconMouseDown: const Color(0xFFFFFFFF),
    );

    return material.Container(
      height: 40,
      color: c.background,
      child: WindowTitleBarBox(
        child: Row(
          children: [
            Expanded(
              child: MoveWindow(
                child: Row(
                  children: [
                    material.Container(width: 16),
                    Text('Querya').semiBold().small(),
                    const Gap(24),
                    Text('File').muted().small(),
                    const Gap(16),
                    Text('Help').muted().small(),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                MinimizeWindowButton(colors: buttonColors),
                MaximizeWindowButton(colors: buttonColors),
                CloseWindowButton(colors: closeButtonColors),
              ],
            )
          ],
        ),
      ),
    );
  }
}
