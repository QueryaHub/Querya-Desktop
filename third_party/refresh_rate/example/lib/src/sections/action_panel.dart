import 'package:flutter/material.dart';

import '../models/action_spec.dart';
import '../ui/panel_widgets.dart';

class ActionPanel extends StatelessWidget {
  const ActionPanel({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<ActionSpec> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                actions.map((action) => ActionButton(spec: action)).toList(),
          ),
          if (footer != null) ...[
            const SizedBox(height: 14),
            footer!,
          ],
        ],
      ),
    );
  }
}
