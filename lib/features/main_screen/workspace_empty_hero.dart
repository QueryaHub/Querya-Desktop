import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/window_layout.dart';
import 'package:querya_desktop/core/theme/querya_colors.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Marketing-style empty workspace: badge, copy, mock window, primary CTA.
class WorkspaceEmptyHero extends StatelessWidget {
  const WorkspaceEmptyHero({
    super.key,
    required this.onNewConnection,
  });

  final VoidCallback onNewConnection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return material.LayoutBuilder(
      builder: (context, c) {
        final vw = c.maxWidth;
        final padH = WindowLayout.heroHorizontalPadding(vw);
        final padV = vw < WindowLayout.compactWindowWidth ? 24.0 : 32.0;
        final maxContent = WindowLayout.heroContentMaxWidth(vw);
        final mockH = WindowLayout.heroMockWindowHeight(maxContent);
        final compact = vw < WindowLayout.compactWindowWidth;
        return material.SingleChildScrollView(
          padding: material.EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: material.Align(
            alignment: material.Alignment.topCenter,
            child: material.ConstrainedBox(
              constraints: material.BoxConstraints(maxWidth: maxContent),
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.center,
                children: [
                  _HeroBadge(colorScheme: cs, compact: compact),
                  material.SizedBox(height: compact ? 16 : 20),
                  material.Padding(
                    padding: const material.EdgeInsets.symmetric(horizontal: 4),
                    child: material.Text(
                      'A lightweight desktop client for every database you ship',
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        fontSize: 20,
                        fontWeight: material.FontWeight.w600,
                        color: cs.foreground,
                      ),
                    ),
                  ),
                  material.SizedBox(height: compact ? 10 : 12),
                  material.Padding(
                    padding: const material.EdgeInsets.symmetric(horizontal: 4),
                    child: material.Text(
                      'Connect to PostgreSQL, MySQL, Redis and MongoDB from a single '
                      'focused app with a calm dark interface.',
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ),
                  const material.SizedBox(height: 10),
                  Text(
                    'BUILT WITH FLUTTER · CROSS-PLATFORM',
                    textAlign: material.TextAlign.center,
                    style: material.TextStyle(
                      fontFamily: QueryaTypography.mono,
                      fontSize: compact ? 9 : 10,
                      letterSpacing: 0.6,
                      color: cs.mutedForeground.withValues(alpha: 0.85),
                    ),
                  ),
                  material.SizedBox(height: compact ? 20 : 28),
                  _MockAppWindow(
                    colorScheme: cs,
                    height: mockH,
                    compact: compact,
                  ),
                  material.SizedBox(height: compact ? 20 : 28),
                  material.Wrap(
                    alignment: material.WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      PrimaryButton(
                        onPressed: onNewConnection,
                        leading: material.Icon(
                          material.Icons.add_link_rounded,
                          size: compact ? 16 : 18,
                        ),
                        child: const Text('New connection'),
                      ),
                    ],
                  ),
                  material.SizedBox(height: compact ? 14 : 18),
                  material.Padding(
                    padding: const material.EdgeInsets.symmetric(horizontal: 8),
                    child: material.Text(
                      'You can also use Connection → New Database Connection. '
                      'Passwords are kept in your OS secure store (see docs/security.md). '
                      'Quick start: docs/user-guide.md.',
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.mutedForeground.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.colorScheme, this.compact = false});

  final ColorScheme colorScheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: material.EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: material.BoxDecoration(
        color: colorScheme.background,
        borderRadius: material.BorderRadius.circular(999),
        border: material.Border.all(
          color: QueryaColors.accentCyan.withValues(alpha: 0.45),
        ),
      ),
      child: material.Row(
        mainAxisSize: material.MainAxisSize.max,
        children: [
          material.Icon(
            material.Icons.auto_awesome_rounded,
            size: compact ? 12 : 14,
            color: colorScheme.primary,
          ),
          material.SizedBox(width: compact ? 6 : 8),
          material.Expanded(
            child: material.Text(
              'One app for SQL and NoSQL',
              maxLines: 2,
              overflow: material.TextOverflow.ellipsis,
              style: material.TextStyle(
                fontSize: compact ? 11 : 12,
                color: colorScheme.foreground.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockAppWindow extends StatelessWidget {
  const _MockAppWindow({
    required this.colorScheme,
    required this.height,
    this.compact = false,
  });

  final ColorScheme colorScheme;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final glow = QueryaColors.accentCyan.withValues(alpha: 0.14);
    final sidebarW = compact ? 58.0 : 72.0;
    final blur = compact ? 28.0 : 40.0;
    final radius = compact ? 12.0 : 16.0;
    return material.Container(
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(radius),
        boxShadow: [
          material.BoxShadow(
            color: glow,
            blurRadius: blur,
            spreadRadius: -4,
            offset: material.Offset(0, compact ? 12 : 18),
          ),
        ],
      ),
      child: material.Container(
        height: height,
        decoration: material.BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: material.BorderRadius.circular(radius),
          border: material.Border.all(
            color: colorScheme.border.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: material.Clip.antiAlias,
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            material.Container(
              padding: material.EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 8 : 10,
              ),
              decoration: material.BoxDecoration(
                border: material.Border(
                  bottom: material.BorderSide(
                    color: colorScheme.border.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: material.Row(
                children: [
                  _trafficDot(const Color(0xFFFF5F57)),
                  const material.SizedBox(width: 6),
                  _trafficDot(const Color(0xFFFEBC2E)),
                  const material.SizedBox(width: 6),
                  _trafficDot(const Color(0xFF28C840)),
                ],
              ),
            ),
            material.Expanded(
              child: material.Row(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Container(
                    width: sidebarW,
                    padding: material.EdgeInsets.fromLTRB(
                      compact ? 8 : 10,
                      compact ? 8 : 10,
                      compact ? 6 : 8,
                      compact ? 8 : 10,
                    ),
                    color: const Color(0xFF0F0F0F),
                    child: material.Column(
                      crossAxisAlignment: material.CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SERVERS',
                          style: material.TextStyle(
                            fontFamily: QueryaTypography.mono,
                            fontSize: compact ? 8 : 9,
                            letterSpacing: 0.5,
                            color: colorScheme.mutedForeground,
                          ),
                        ),
                        material.SizedBox(height: compact ? 8 : 10),
                        material.Container(
                          padding: material.EdgeInsets.symmetric(
                            horizontal: compact ? 6 : 8,
                            vertical: compact ? 4 : 6,
                          ),
                          decoration: material.BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius:
                                material.BorderRadius.circular(compact ? 6 : 8),
                          ),
                          child: material.Text(
                            'analytics-prod',
                            maxLines: 1,
                            overflow: material.TextOverflow.ellipsis,
                            style: material.TextStyle(
                              fontSize: compact ? 9 : 10,
                              color: colorScheme.foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  material.Expanded(
                    child: material.Container(
                      margin: material.EdgeInsets.all(compact ? 8 : 10),
                      padding: material.EdgeInsets.all(compact ? 8 : 10),
                      decoration: material.BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: material.BorderRadius.circular(8),
                        border: material.Border.all(
                          color: colorScheme.border.withValues(alpha: 0.25),
                        ),
                      ),
                      child: material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        children: [
                          material.Text(
                            'SELECT …',
                            style: material.TextStyle(
                              fontFamily: QueryaTypography.mono,
                              fontSize: compact ? 9 : 11,
                              height: 1.45,
                              color: colorScheme.primary,
                            ),
                          ),
                          material.Text(
                            "  interval '1 day'",
                            style: material.TextStyle(
                              fontFamily: QueryaTypography.mono,
                              fontSize: compact ? 9 : 11,
                              height: 1.45,
                              color: const Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

material.Widget _trafficDot(Color c) {
  return material.Container(
    width: 10,
    height: 10,
    decoration: material.BoxDecoration(
      color: c,
      shape: material.BoxShape.circle,
    ),
  );
}
